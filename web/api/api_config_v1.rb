#

require 'json'
require 'api_utils'

module Hanlon
  module WebService
    module Config

      class APIv1 < Grape::API

        version :v1, :using => :path, :vendor => "hanlon"
        format :json
        default_format :json
        SLICE_REF = ProjectHanlon::Slice::Config.new([])

        rescue_from Grape::Exceptions::Validation do |e|
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

          def is_uuid?(string_)
            string_ =~ /^[A-Za-z0-9]{1,22}$/
          end

          def request_is_from_hanlon_server(ip_addr)
            Hanlon::WebService::Utils::request_from_hanlon_server?(ip_addr)
          end

          def slice_success_response(slice, command, response, options = {})
            Hanlon::WebService::Utils::hnl_slice_success_response(slice, command, response, options)
          end

        end

        # the following description hides this endpoint from the swagger-ui-based documentation
        # (since the functionality provided by this endpoint is not intended to be used off of
        # the Hanlon server)
        desc 'Hide this endpoint', {
            :hidden => true
        }
        resource :config do
          # GET /config
          # Query for Hanlon server configuration
          desc "Retrieve the current Hanlon server configuration"
          before do
            # only test if directly accessing the /config resource
            if env["PATH_INFO"].match(/config$/)
              # only allow access to configuration resource from the hanlon server
              unless request_is_from_hanlon_server(env['REMOTE_ADDR'])
                raise ProjectHanlon::Error::Slice::MethodNotAllowed, "Remote Access Forbidden; access to /config resource is only allowed from Hanlon server"
              end
            end
          end
          get do
            config = JSON(ProjectHanlon.config.to_json)
            slice_success_response(SLICE_REF, :get_config, config, :success_type => :generic)
          end      # end GET /config

          resource :ipxe do
            # GET /config/ipxe
            # Query for iPXE boot script to use (with Hanlon)
            desc "Retrieve the iPXE-bootstrap script to use (with Hanlon)"
            get do
              @ipxe_options = {}
              @ipxe_options[:style] = :new
              @ipxe_options[:uri] =  ProjectHanlon.config.hanlon_uri
              @ipxe_options[:websvc_root] =  ProjectHanlon.config.websvc_root
              @ipxe_options[:timeout_sleep] = IPXE_TIMEOUT
              @ipxe_options[:nic_max] = IPXE_NIC_MAX
              env['api.format'] = :text
              ERB.new(File.read(IPXE_ERB)).result(binding)
            end     # end GET /config/ipxe
          end     # end resource /config/ipxe
        end     # end resource /config

      end
    end
  end
end
