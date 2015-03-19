#

require 'json'
require 'api_utils'

module Hanlon
  module WebService
    module ActiveModel
      class APIv1 < Grape::API
        include(ProjectHanlon::Logging)

        version :v1, :using => :path, :vendor => "hanlon"
        format :json
        default_format :json
        SLICE_REF = ProjectHanlon::Slice::ActiveModel.new([])

        rescue_from ProjectHanlon::Error::Slice::InvalidUUID,
                    Grape::Exceptions::Validation do |e|
          Rack::Response.new(
              Hanlon::WebService::Response.new(400, e.class.name, e.message).to_json,
              400,
              { "Content-type" => "application/json" }
          )
        end

        rescue_from ProjectHanlon::Error::Slice::MethodNotAllowed,
                    ProjectHanlon::Error::Slice::CouldNotRemove do |e|
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

          def get_data_ref
            Hanlon::WebService::Utils::get_data
          end

          def request_is_from_hanlon_server(ip_addr)
            Hanlon::WebService::Utils::request_from_hanlon_server?(ip_addr)
          end

          def request_is_from_hanlon_subnet(ip_addr)
            Hanlon::WebService::Utils::request_from_hanlon_subnet?(ip_addr)
          end

          def get_active_model_by_uuid(uuid)
            active_model = SLICE_REF.get_object("active_model_instance", :active, uuid)
            raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Active Model with UUID: [#{uuid}]" unless active_model && (active_model.class != Array || active_model.length > 0)
            active_model
          end

          def remove_active_model(active_model, from_method_symbolic_name)
            raise ProjectHanlon::Error::Slice::CouldNotRemove, "Could not remove Active Model [#{active_model.uuid}]" unless get_data_ref.delete_object(active_model)
            slice_success_response(SLICE_REF, from_method_symbolic_name, "Active Model [#{active_model.uuid}] removed", :success_type => :removed)
          end

          def get_logs_for_active_model(active_model, with_uuid = false)
            # Take each element in our attributes_hash and store as a HashPrint object in our array
            last_time = nil
            first_time = nil
            log_entries = []
            index = 0
            active_model.model.log.each { |log_entry|
              entry_time = Time.at(log_entry["timestamp"])
              entry_time_int = entry_time.to_i
              first_time ||= entry_time
              last_time ||= entry_time
              total_time_diff = entry_time - first_time
              last_time_diff = entry_time - last_time
              hash_entry = { :State => active_model.state_print(log_entry["old_state"].to_s,log_entry["state"].to_s),
                             :Action => log_entry["action"].to_s,
                             :Result => log_entry["result"].to_s,
                             :Time => entry_time.strftime('%Y-%m-%d %H:%M:%S %Z'),
                             :Last => active_model.pretty_time(last_time_diff.to_i),
                             :Total => active_model.pretty_time(total_time_diff.to_i)
              }
              hash_entry[:NodeUUID] = active_model.node_uuid if with_uuid
              log_entries << hash_entry
              last_time = Time.at(log_entry["timestamp"])
              index = index + 1
            }
            log_entries
          end

          def slice_success_response(slice, command, response, options = {})
            Hanlon::WebService::Utils::hnl_slice_success_response(slice, command, response, options)
          end

          def slice_success_object(slice, command, response, options = {})
            Hanlon::WebService::Utils::hnl_slice_success_object(slice, command, response, options)
          end

        end

        resource :active_model do

          # GET /active_model
          # Retrieve list of active_models (or if a 'node_uuid' or 'hw_id' is provided, retrieve the details
          # for the active_model bound to the specified node instead)
          desc "Retrieve a list of all active_model instances"
          params do
            optional :node_uuid, type: String, desc: "The (Hanlon-assigned) UUID of the bound node."
            optional :hw_id, type: String, desc: "The Hardware ID (SMBIOS UUID) of the bound node."
          end
          get do
            node_uuid = params[:node_uuid]
            hw_id = params[:hw_id].upcase if params[:hw_id]
            raise ProjectHanlon::Error::Slice::InvalidCommand, "only one node selection parameter ('hw_id' or 'node_uuid') may be used" if (hw_id && node_uuid)
            # if either a node_uuid or a hw_id was provided, return the details for the active_model bound to the node
            # with that node_id, otherwise just return the list of all active_models
            if hw_id || node_uuid
              engine = ProjectHanlon::Engine.instance
              if hw_id
                node = engine.lookup_node_by_hw_id({:uuid => hw_id, :mac_id => []})
                raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Node with Hardware ID: [#{hw_id}]" unless node
                node_id = hw_id
              elsif node_uuid
                node = SLICE_REF.return_objects_using_uuid(:node, node_uuid)
                raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Node with UUID: [#{node_uuid}]" unless node
                node_id = node_uuid
              end
              active_model = engine.find_active_model(node)
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Node [#{node_id}] is not bound to an active_model" unless active_model
              slice_success_object(SLICE_REF, :get_all_active_models, active_model, :success_type => :generic)
            else
              active_models = SLICE_REF.get_object("active_models", :active)
              slice_success_object(SLICE_REF, :get_all_active_models, active_models, :success_type => :generic)
            end
          end     # end GET /active_model

          # DELETE /active_model
          # remove an active_model instance bound to a node with the given Hanlon-assigned 'node_uuid'
          # or with the given 'hw_id' (SMBIOS UUID)
          params do
            optional :node_uuid, type: String, desc: "The (Hanlon-assigned) UUID of the bound node."
            optional :hw_id, type: String, desc: "The Hardware ID (SMBIOS UUID) of the bound node."
          end
          delete do
            node_uuid = params[:node_uuid]
            hw_id = params[:hw_id].upcase if params[:hw_id]
            raise ProjectHanlon::Error::Slice::InvalidCommand, "must select a node using one of the 'hw_id' or 'node_uuid' query parameters" unless (hw_id || node_uuid)
            raise ProjectHanlon::Error::Slice::InvalidCommand, "only one node selection parameter ('hw_id' or 'node_uuid') may be used" if (hw_id && node_uuid)
            # find the matching node; either by Hardware ID (SMBIOS UUID) or Hanlon-assigned UUID
            engine = ProjectHanlon::Engine.instance
            if hw_id
              node = engine.lookup_node_by_hw_id({:uuid => hw_id, :mac_id => []})
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Node with Hardware ID: [#{hw_id}]" unless node
              node_id = hw_id
            else
              node = SLICE_REF.return_objects_using_uuid(:node, node_uuid)
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Node with UUID: [#{node_uuid}]" unless node
              node_id = node_uuid
            end
            raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Node: [#{node_id}]" unless node
            active_model = engine.find_active_model(node)
            raise ProjectHanlon::Error::Slice::InvalidUUID, "Node [#{node_id}] is not bound to an active_model" unless active_model
            remove_active_model(active_model, :remove_active_model_by_hw_id)
          end

          # the following description hides this endpoint from the swagger-ui-based documentation
          # (since the functionality provided by this endpoint is not intended to be used off of
          # the Hanlon server)
          desc 'Hide this endpoint', {
              :hidden => true
          }
          resource '/logs' do

            # GET /active_model
            # Retrieve all active_model logs.
            desc "Returns the log entries for all active_model instances"
            before do
              # only allow access to this resource from the Hanlon subnet
              unless request_is_from_hanlon_server(env['REMOTE_ADDR'])
                raise ProjectHanlon::Error::Slice::MethodNotAllowed, "Remote Access Forbidden; access to /active_model/logs resource is only allowed from Hanlon server"
              end
            end
            get do
              active_models = SLICE_REF.get_object("active_models", :active)
              log_items = []
              active_models.each { |bp| log_items = log_items | get_logs_for_active_model(bp, true) }
              log_items.sort! { |a, b| a[:Time] <=> b[:Time] }
              slice_success_response(SLICE_REF, :get_active_model_logs, log_items, :success_type => :generic)
            end     # end GET /active_model/logs

          end     # end resource /active_model/logs

          resource '/:uuid' do

            # GET /active_model/{uuid}
            # Retrieve a specific active_model (by UUID).
            desc "Return the details for a specific active_model instance"
            params do
              requires :uuid, type: String, desc: "The active_model's UUID"
            end
            get do
              uuid = params[:uuid]
              active_model = get_active_model_by_uuid(uuid)
              slice_success_object(SLICE_REF, :get_active_model_by_uuid, active_model, :success_type => :generic)
            end     # end GET /active_model/{uuid}


            # DELETE /active_model/{uuid}
            # Remove an active_model instance (by UUID)
            desc "Remove an active_model instance"
            before do
              # only allow access to this resource from the Hanlon subnet
              unless request_is_from_hanlon_subnet(env['REMOTE_ADDR'])
                raise ProjectHanlon::Error::Slice::MethodNotAllowed, "Remote Access Forbidden; access to /active_model/{uuid} resource is only allowed from Hanlon subnet"
              end
            end
            params do
              requires :uuid, type: String, desc: "The active_model's UUID"
            end
            delete do
              active_model_uuid = params[:uuid]
              active_model = SLICE_REF.get_object("active_model_instance", :active, active_model_uuid)
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Active Model with UUID: [#{active_model_uuid}]" unless active_model && (active_model.class != Array || active_model.length > 0)
              remove_active_model(active_model, :remove_active_model_by_uuid)
            end     # end DELETE /active_model/{uuid}

            # the following description hides this endpoint from the swagger-ui-based documentation
            # (since the functionality provided by this endpoint is not intended to be used off of
            # the Hanlon server)
            desc 'Hide this endpoint', {
                :hidden => true
            }
            resource '/logs' do

              # GET /active_model/{uuid}/logs
              # Retrieve the log for an active_model (by UUID).
              desc "Returns the log entries for a specific active_model instance"
              before do
                # only allow access to this resource from the Hanlon subnet
                unless request_is_from_hanlon_server(env['REMOTE_ADDR'])
                  raise ProjectHanlon::Error::Slice::MethodNotAllowed, "Access to /active_model/{uuid}/logs resource is only allowed from Hanlon server"
                end
              end
              params do
                requires :uuid, type: String, desc: "The active_model's UUID"
              end
              get do
                uuid = params[:uuid]
                active_model = get_active_model_by_uuid(uuid)
                log_items = get_logs_for_active_model(active_model)
                slice_success_response(SLICE_REF, :get_active_model_logs, log_items, :success_type => :generic)
              end     # end GET /active_model/{uuid}/logs

            end     # end resource /active_model/:uuid/logs

          end     # end resource /active_model/:uuid

        end     # end resource /active_model

      end

    end

  end

end
