#

require 'json'
require 'api_utils'

module Hanlon
  module WebService
    module Boot

      class APIv1 < Grape::API

        version :v1, :using => :path, :vendor => "hanlon"
        format :json
        default_format :json

        rescue_from ProjectHanlon::Error::Slice::InvalidCommand,
                    ProjectHanlon::Error::Slice::MissingArgument,
                    Grape::Exceptions::Validation do |e|
          Rack::Response.new(
              Hanlon::WebService::Response.new(400, e.class.name, e.message).to_json,
              400,
              { "Content-type" => "application/json" }
          )
        end

        rescue_from ProjectHanlon::Error::Slice::MethodNotAllowed do |e|
          Rack::Response.new(
              Hanlon::WebService::Response.new(403, e.class.name, e.message).to_json,
              403,
              { "Content-type" => "application/json" }
          )
        end

        rescue_from :all do |e|
          #raise e
          puts "An internal error occuring serving this request #{e.message}"
          puts e.backtrace
          Rack::Response.new(
              Hanlon::WebService::Response.new(500, e.class.name, e.message).to_json,
              500,
              { "Content-type" => "application/json" }
          )
        end

        helpers do

          def content_type_header
            settings[:content_types][env['api.format']]
          end

          def api_format
            env['api.format']
          end

          def request_is_from_hanlon_subnet(ip_addr)
            Hanlon::WebService::Utils::request_from_hanlon_subnet?(ip_addr)
          end

        end

        # the following code snippet hides this endpoint from the swagger-ui-based documentation
        # (since the functionality provided by this endpoint is not intended to for users, instead
        # this functionality is used during the iPXE boot process to retrieve the appropriate
        # iPXE-boot script for a given node based on it's hardware ID nad the MAC address of the
        # interface that it received it's DHCP assignment from)
        desc 'Hide this endpoint', {
            :hidden => true
        }
        resource :boot do

          # GET /boot
          # Query for the boot script for a node
          #   parameters:
          #         required:
          #           :dhcp_mac | String | The MAC address the DHCP NIC.          |      | Default: unavailable
          #         optional (although one of these two must be specified):
          #           :uuid     | String | The UUID for the node (from the BIOS). |      | Default: unavailable
          #           :mac_id   | String | The MAC addresses for the node's NICs. |      | Default: unavailable
          #         allowed for backwards compatibility (although will throw an error if used with 'mac_id')
          #           :hw_id    | String | The MAC addresses for the node's NICs. |      | Default: unavailable
          desc "Retrieve the iPXE-boot script (for a node)"
          before do
            # only allow access to this resource from the Hanlon subnet
            unless request_is_from_hanlon_subnet(env['REMOTE_ADDR'])
              env['api.format'] = :text
              raise ProjectHanlon::Error::Slice::MethodNotAllowed, "Remote Access Forbidden; access to /boot resource is not allowed from outside of the Hanlon subnet"
            end
          end
          params do
            requires :dhcp_mac, type: String, desc: "The MAC address of the DHCP NIC"
            optional :uuid, type: String, desc: "The UUID for the node"
            optional :mac_id, type: String, desc: "The MAC addresses of the node's NICs."
            optional :hw_id, type: String, desc: "The MAC addresses of the node's NICs."
          end
          get do
            uuid = params[:uuid].upcase if params[:uuid]
            mac_id = params[:mac_id].upcase.split("_") if params[:mac_id]
            # the following parameter is only used for backwards compatibility (with
            # previous versions of Hanlon, which used a 'hw_id' field during the boot
            # process instead of the new 'mac_id' field)
            hw_id = params[:hw_id].upcase.split("_") if params[:hw_id]
            raise ProjectHanlon::Error::Slice::InvalidCommand, "The hw_id parameter is only allowed for backwards compatibility; use with the mac_id parameter is not allowed" if (hw_id && mac_id)
            mac_id = hw_id if hw_id
            raise ProjectHanlon::Error::Slice::MissingArgument, "At least one of the optional arguments (uuid or mac_id) must be specified" unless ((uuid && uuid.length > 0) || (mac_id && !(mac_id.empty?)))
            dhcp_mac = params[:dhcp_mac]
            mac_id.collect! {|x| x.upcase.gsub(':', '') } if mac_id
            env['api.format'] = :text
            ProjectHanlon::Engine.instance.boot_checkin(:uuid => uuid, :mac_id => mac_id, :dhcp_mac => dhcp_mac)
          end     # end GET /boot

        end     # end resource /boot

      end

    end

  end

end
