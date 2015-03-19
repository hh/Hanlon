#

require 'json'
require 'api_utils'

module Hanlon
  module WebService
    module Model

      class APIv1 < Grape::API

        version :v1, :using => :path, :vendor => "hanlon"
        format :json
        default_format :json
        SLICE_REF = ProjectHanlon::Slice::Model.new([])

        rescue_from ProjectHanlon::Error::Slice::InvalidUUID,
                    ProjectHanlon::Error::Slice::MissingArgument,
                    ProjectHanlon::Error::Slice::InvalidModelTemplate,
                    ProjectHanlon::Error::Slice::InvalidModelMetadata,
                    ProjectHanlon::Error::Slice::MissingModelMetadata,
                    Grape::Exceptions::Validation do |e|
          Rack::Response.new(
              Hanlon::WebService::Response.new(400, e.class.name, e.message).to_json,
              400,
              { "Content-type" => "application/json" }
          )
        end

        rescue_from ProjectHanlon::Error::Slice::CouldNotCreate,
                    ProjectHanlon::Error::Slice::CouldNotUpdate,
                    ProjectHanlon::Error::Slice::CouldNotRemove do |e|
          Rack::Response.new(
              Hanlon::WebService::Response.new(403, e.class.name, e.message).to_json,
              403,
              { "Content-type" => "application/json" }
          )
        end

        rescue_from ProjectHanlon::Error::Slice::InternalError do |e|
          Rack::Response.new(
              Hanlon::WebService::Response.new(500, e.class.name, e.message).to_json,
              500,
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

          def slice_success_response(slice, command, response, options = {})
            Hanlon::WebService::Utils::hnl_slice_success_response(slice, command, response, options)
          end

          def slice_success_object(slice, command, response, options = {})
            Hanlon::WebService::Utils::hnl_slice_success_object(slice, command, response, options)
          end

        end

        resource :model do

          # GET /model
          # Query for defined models.
          desc "Retrieve a list of all model instances"
          get do
            models = SLICE_REF.get_object("models", :model)
            slice_success_object(SLICE_REF, :get_all_models, models, :success_type => :generic)
          end     # end GET /model

          # POST /model
          # Create a Hanlon model
          #   parameters:
          #     template            | String | The "template" to use for the new model            |         | Default: unavailable
          #     label               | String | The "label" to use for the new model               |         | Default: unavailable
          #     optional            | String | The UUID of the image to use                       |         | Default: "false"
          #     req_metadata_params | Hash   | The metadata parameters to use for the new model   |         | Default: unavailable
          desc "Create a new model instance"
          params do
            requires "template", type: String, desc: "The model template to use"
            requires "label", type: String, desc: "The new model's label"
            optional "image_uuid", type: String, default: "false", desc: "The UUID of the image to use"
            requires "req_metadata_params", type: Hash, desc: "The (JSON) metadata hash parameters"
          end
          post do
            template = params["template"]
            label = params["label"]
            image_uuid = params["image_uuid"] unless params["image_uuid"] == "false"
            req_metadata_params = params["req_metadata_params"]
            # check the values that were passed in
            model = SLICE_REF.get_model_using_template_name(template)
            is_noop_template = ["boot_local", "discover_only"].include?(template)
            raise ProjectHanlon::Error::Slice::InvalidModelTemplate, "Invalid Model Template [#{template}] " unless model
            raise ProjectHanlon::Error::Slice::InputError, "Cannot add an image to a 'noop' model" if image_uuid && is_noop_template
            image = model.image_prefix ? SLICE_REF.verify_image(model, image_uuid) : nil if image_uuid
            raise ProjectHanlon::Error::Slice::InvalidUUID, "Invalid Image UUID [#{image_uuid}] " unless is_noop_template || image
            # use the arguments passed in (above) to create a new model
            raise ProjectHanlon::Error::Slice::MissingArgument, "Must Provide Required Metadata Parameters [req_metadata_params]" unless req_metadata_params
            model.label = label
            model.image_uuid = image.uuid if image
            model.is_template = false
            # for both the req_metadata_hash and the opt_metadata_hash, extract the values that
            # were supplied in the req_metadata_params and add them to the underlying model
            [model.req_metadata_hash, model.opt_metadata_hash].each { |md_hash|
              md_hash.each { |key, md_hash_value|
                # strip off the '@' prefix from the req_metadata_hash key to get the
                # corresponding key in the input req_metadata_params hash map
                param_key = key[1..-1]
                value = req_metadata_params[param_key]
                # if the value doesn't exist in the req_metadata_params, then set the underlying instance
                # variable to the default value for this field (if it exists) and move on to the next
                # req_metadata_hash field
                unless value && !value.empty?
                  val_set = model.set_default_metadata_value(key, md_hash)
                  raise ProjectHanlon::Error::Slice::InputError, "No value supplied and no valid default available for #{param_key} field in req_metadata_params hash" unless val_set
                  next
                end
                # set the instance variable in the underlying model object (creates a new instance variable dynamically);
                # note that if the value passed through isn't a valid value (the req_metadata_hash includes a regular
                # expression that must be matched for any value to be considered as a 'valid' value), then an error
                # will be thrown here
                val_set = model.set_metadata_value(key, value, md_hash)
                raise ProjectHanlon::Error::Slice::InputError, "Invalid value #{value} for #{param_key} field in req_metadata_params hash" unless val_set
              }
            } if req_metadata_params && !req_metadata_params.empty?
            get_data_ref.persist_object(model)
            raise(ProjectHanlon::Error::Slice::CouldNotCreate, "Could not create Model") unless model
            slice_success_object(SLICE_REF, :create_model, model, :success_type => :created)
          end     # end POST /model

          resource :templates do

            # GET /model/templates
            # Query for available model templates
            desc "Retrieve a list of available model templates"
            get do
              # get the model templates (as an array)
              model_templates = SLICE_REF.get_child_templates(ProjectHanlon::ModelTemplate)
              # then, construct the response
              slice_success_object(SLICE_REF, :get_model_templates, model_templates, :success_type => :generic)
            end     # end GET /model/templates

            resource '/:name' do

              # GET /model/templates/{name}
              # Query for a specific model template (by name)
              desc "Retrieve details for a specific model template (by name)"
              params do
                requires :name, type: String, desc: "The model template name"
              end
              get do
                # get the matching model template
                model_template_name = params[:name]
                model_templates = SLICE_REF.get_child_templates(ProjectHanlon::ModelTemplate)
                model_template = model_templates.select { |template| template.name == model_template_name }
                raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Model Template Named: [#{model_template_name}]" unless model_template && (model_template.class != Array || model_template.length > 0)
                # then, construct the response
                slice_success_object(SLICE_REF, :get_model_template_by_uuid, model_template[0], :success_type => :generic)
              end     # end GET /model/templates/{name}

            end     # end resource /:name

          end     # end resource :templates

          resource '/:uuid' do

            # GET /model/{uuid}
            # Query for the state of a specific model.
            desc "Retrieve details for a specific model instance (by UUID)"
            params do
              requires :uuid, type: String, desc: "The model's UUID"
            end
            get do
              model_uuid = params[:uuid]
              model = SLICE_REF.get_object("get_model_by_uuid", :model, model_uuid)
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Model with UUID: [#{model_uuid}]" unless model && (model.class != Array || model.length > 0)
              slice_success_object(SLICE_REF, :get_model_by_uuid, model, :success_type => :generic)
            end     # end GET /model/{uuid}

            # PUT /model/{uuid}
            # Update a Hanlon model (any of the the label, image UUID, or req_metadata_params
            # can be updated using this endpoint; note that the model template cannot be updated
            # once a model is created
            #   parameters:
            #     label               | String | The "label" to use for the new model               |         | Default: unavailable
            #     image_uuid          | String | The UUID of the image to use                       |         | Default: "false"
            #     req_metadata_params | Hash   | The metadata parameters to use for the new model   |         | Default: unavailable
            desc "Update a model instance (by UUID)"
            params do
              requires :uuid, type: String, desc: "The model's UUID"
              optional "label", type: String, desc: "The model's new label"
              optional "image_uuid", type: String, default: "false", desc: "The new image (by UUID)"
              optional "req_metadata_params", type: Hash, desc: "The (JSON) metadata hash parameters"
            end
            put do
              # get the input parameters that were passed in as part of the request
              # (at least one of these should be a non-nil value)
              label = params["label"]
              image_uuid = params["image_uuid"] unless params["image_uuid"] == "false"
              req_metadata_params = params["req_metadata_params"]
              # get the UUID for the model being updated
              model_uuid = params[:uuid]
              # check the values that were passed in (and gather new meta-data if
              # the --change-metadata flag was included in the update command and the
              # command was invoked via the CLI...it's an error to use this flag via
              # the RESTful API, the req_metadata_params should be used instead)
              model = SLICE_REF.get_object("model_with_uuid", :model, model_uuid)
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Invalid Model UUID [#{model_uuid}]" unless model && (model.class != Array || model.length > 0)
              model.label = label if label
              raise ProjectHanlon::Error::Slice::InputError, "Cannot add an image to a 'noop' model" if image_uuid && [:boot_local, :discover_only].include?(model.template)
              image = model.image_prefix ? SLICE_REF.verify_image(model, image_uuid) : nil if image_uuid
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Invalid Image UUID [#{image_uuid}] " unless image || !image_uuid
              model.image_uuid = image.uuid if image
              if req_metadata_params
                req_metadata_params.each { |key, value|
                  # add an '@' prefix from the req_metadata_params key to get the name
                  # of the corresponding instance variable in the underlying model instance
                  model_key = "@#{key}"
                  # throw an error if don't find a required key in the model's req_metadata_hash
                  md_hash_value = model.req_metadata_hash[model_key]
                  raise ProjectHanlon::Error::Slice::InputError, "Unrecognized field #{key} in req_metadata_params hash" unless md_hash_value
                  # set the instance variable in the underlying model object (creates a new instance variable dynamically);
                  # note that if the value passed through isn't a valid value (the req_metadata_hash includes a regular
                  # expression that must be matched for any value to be considered as a 'valid' value), then an error
                  # will be thrown here
                  val_set = model.set_metadata_value(model_key, value)
                  raise ProjectHanlon::Error::Slice::InputError, "Invalid value #{value} for #{key} field in req_metadata_params hash" unless val_set
                }
              end
              raise ProjectHanlon::Error::Slice::CouldNotUpdate, "Could not update Model [#{model.uuid}]" unless model.update_self
              slice_success_object(SLICE_REF, :update_model, model, :success_type => :updated)
            end     # end PUT /model/{uuid}

            # DELETE /model/{uuid}
            # Remove a Hanlon model (by UUID)
            desc "Remove a model instance (by UUID)"
            params do
              requires :uuid, type: String, desc: "The model's UUID", desc: "The model's UUID"
            end
            delete do
              model_uuid = params[:uuid]
              model = SLICE_REF.get_object("model_with_uuid", :model, model_uuid)
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Model with UUID: [#{model_uuid}]" unless model && (model.class != Array || model.length > 0)
              # Use the Engine instance to remove the selected model from the database
              engine = ProjectHanlon::Engine.instance
              begin
                engine.remove_model(model)
                raise ProjectHanlon::Error::Slice::CouldNotRemove, "Could not remove Model [#{model.uuid}]" unless engine.remove_model(model)
              rescue RuntimeError => e
                raise ProjectHanlon::Error::Slice::InternalError, e.message
              rescue Exception => e
                # if got to here, then the Engine raised an exception
                raise ProjectHanlon::Error::Slice::CouldNotRemove, e.message
              end
              slice_success_response(SLICE_REF, :remove_model_by_uuid, "Model [#{model.uuid}] removed", :success_type => :removed)
            end     # end DELETE /model/{uuid}

          end     # end resource /:uuid

        end     # end resource :model

      end

    end

  end

end
