require "json"
require "pry"

# Root ProjectHanlon namespace
module ProjectHanlon
  module ModelTemplate
    # Root Model object
    # @abstract
    class Base < ProjectHanlon::Object
      include(ProjectHanlon::Logging)

      attr_accessor :name
      attr_accessor :label
      attr_accessor :template
      attr_accessor :description
      attr_accessor :hidden
      attr_accessor :callback
      attr_accessor :current_state
      attr_accessor :node_bound
      attr_accessor :broker_plugin
      attr_accessor :final_state
      attr_accessor :counter
      attr_accessor :log
      attr_accessor :req_metadata_hash
      attr_accessor :opt_metadata_hash

      # init
      # @param hash [Hash]
      def initialize(hash)
        super()
        @name = "model_base"
        @hidden = true
        @template = :base
        @noun = "model"
        @description = "Base model template"
        @req_metadata_hash = {}
        @opt_metadata_hash = {}
        @callback = {}
        @current_state = :init
        @node = nil
        @policy_bound = nil
        @broker_plugin = false # by default
        @final_state = :nothing
        @counter = 0
        @result = nil
        # Model Log
        @log = []
        @_namespace = :model
        from_hash(hash) unless hash == nil
      end

      def callback_init(callback_namespace, args_array, node, policy_uuid, broker)
        @broker = broker
        @args_array = args_array
        @node = node
        @policy_uuid = policy_uuid
        logger.debug "callback method called #{callback_namespace}"
        self.send(callback_namespace)
      end

      def fsm
        # used to defined base tree elements like Broker
        base_fsm_tree = {
            :broker_fail => {
                :else => :broker_fail,
                :retry => @final_state},
            :broker_wait => {
                :else => :broker_wait},
            :broker_success => {
                :else => :broker_success},
            :complete_no_broker => {
                :else => :complete_no_broker}
        }
        fsm_tree.merge base_fsm_tree
      end

      def fsm_tree
        # Overridden with custom tree within child model
        {}
      end

      def fsm_action(action, method)
        # We only change state if we have a node bound
        if @node
          old_state = @current_state
          old_state = :init unless old_state
          binding.pry if @current_state.class == String #ENV['DEBUG']
          # not sure why this shows up as as string
          # when we use the memory persists
          @current_state = @current_state.to_sym
          begin
            if fsm[@current_state][action] != nil
              @current_state = fsm[@current_state][action]
            else
              @current_state = fsm[@current_state][:else]
            end
          rescue => e
            logger.error "FSM ERROR: #{e.message}"
            raise e
          end

        else
          logger.debug "Action #{action} called with state #{@current_state} but no Node bound"
        end
        fsm_log(:state => @current_state,
                :old_state => old_state,
                :action => action,
                :method => method,
                :node_uuid => @node.uuid,
                :timestamp => Time.now.to_i)
        # If in final state we check broker assignment
        if @current_state.to_s == @final_state.to_s # Enable to help with broker debug || @current_state.to_s == "broker_fail"
          broker_check
        end
      end

      def fsm_log(options)
        logger.debug "state update: #{options[:old_state]} => #{options[:state]} on #{options[:action]} for #{options[:node_uuid]}"
        options[:result] = @result
        options[:result] ||= "n/a"
        @log << options
        @result = nil
      end

      def broker_check
        # We need to check if a broker is attached
        unless @broker
          logger.error "No broker defined"
          @result = "No broker attached"
          @current_state = :complete_no_broker
          fsm_log(:state => @current_state,
                  :old_state => @final_state,
                  :action => :broker_check,
                  :method => :broker_check,
                  :node_uuid => @node.uuid,
                  :timestamp => Time.now.to_i)
          return
        end
        case @broker_plugin
          when :agent
            return broker_agent_handoff
          when :proxy
            return broker_proxy_handoff
          else
            return false # Brokers disabled for model
        end
      end

      def broker_agent_handoff
        # Implemented by child model
        false
      end

      def broker_proxy_handoff
        # Implemented by child model
        false
      end

      def node_metadata
        begin
          logger.debug "Building metadata"
          meta = {}
          logger.debug "Adding hanlon stuff"
          meta[:hanlon_tags] = @node.tags.join(',')
          meta[:hanlon_node_uuid] = @node.uuid
          meta[:hanlon_active_model_uuid] = @policy_uuid
          meta[:hanlon_model_uuid] = @uuid
          meta[:hanlon_model_name] = @name
          meta[:hanlon_model_description] = @description
          meta[:hanlon_model_template] = @template.to_s
          meta[:hanlon_policy_count] = @counter.to_s
          logger.debug "Finished metadata build"
        rescue => e
          logger.error "metadata error: #{e}"
        end
        meta
      end

      def callback_url(namespace, action)
        "#{api_svc_uri}/policy/callback/#{@policy_uuid}/#{namespace}/#{action}"
      end

      def print_header
        if @is_template
          return "Template Name", "Description"
        else
          return "Label", "Template", "Description", "UUID"
        end
      end

      def print_item
        if @is_template
          return @name.to_s, @description.to_s
        else
          image_uuid_str = image_uuid ? image_uuid : "n/a"
          return @label, @template.to_s, @description, @uuid, image_uuid_str
        end
      end

      def print_item_header
        if @is_template
          return "Template Name", "Description"
        else
          return "Label", "Template", "Description", "UUID", "Image UUID"
        end
      end

      def print_items
        if @is_template
          return @name.to_s, @description.to_s
        else
          return @label, @template.to_s, @description, @uuid
        end
      end

      def line_color
        :white_on_black
      end

      def header_color
        :red_on_black
      end

      def config
        ProjectHanlon.config
      end

      def api_svc_uri
        "http://#{config.hanlon_server}:#{config.api_port}#{config.websvc_root}"
      end

      def image_svc_uri
        "#{api_svc_uri}/image/#{@image_prefix}"
      end

      def static_uri
        "#{api_svc_uri}/static"
      end

      def yaml_read_metadata(yaml_metadata_hash)
        req_metadata_params = {}
        # set instance variables for the required values in the input yaml_metadata_hash
        req_meta_vals = yaml_metadata_hash.select{ |key| req_metadata_hash.keys.include?("@#{key}") }
        req_meta_vals.each { |key, value|
          model_key = "@#{key}"
          flag = set_metadata_value(model_key, value)
          if !flag
            raise ProjectHanlon::Error::Slice::InvalidModelMetadata, "Invalid Metadata [#{key}:#{value}]"
          end
          req_metadata_params[key] = value
        }
        # set instance variables for the optional values in the input yaml_metadata_hash
        optional_vals = yaml_metadata_hash.reject{ |key| req_metadata_hash.keys.include?("@#{key}") }
        optional_vals.each { |key, value|
          model_key = "@#{key}"
          flag = set_metadata_value(model_key, value, opt_metadata_hash)
          if !flag
            raise ProjectHanlon::Error::Slice::InvalidModelMetadata, "Invalid Metadata [#{key}:#{value}]"
          end
          req_metadata_params[key] = value
        }
        # determine which keys are still missing from the req_metadata_hash
        # keys list, will ask for these using the CLI; note that if the input
        # 'yaml_metadata_hash' map was empty, this operation will return all
        # of the keys in the 'req_metadata_hash'
        [(req_metadata_hash.keys - yaml_metadata_hash.keys.map { |key| "@#{key}" } ), req_metadata_params]
      end

      def cli_get_metadata_params(yaml_metadata_hash = {})
        puts "--- Building Model (#{name}): #{label}\n".yellow
        # will return a list of the fields from the req_metadata_hash that were
        # not provided in the input yaml_metadata_hash map
        remaining_keys, req_metadata_params = yaml_read_metadata(yaml_metadata_hash)
        # req_metadata_hash.each { |key, metadata|
        remaining_keys.each { |model_key|
          key = model_key[1..-1]
          metadata = req_metadata_hash[model_key]
          metadata = map_keys_to_symbols(metadata)
          flag = false
          val = nil
          until flag
            print "Please enter " + "#{metadata[:description]}".yellow.bold
            print " (example: " + "#{metadata[:example]}".yellow + ") \n"
            puts "default: " + "#{metadata[:default]}".yellow if metadata[:default] != ""
            puts metadata[:required] ? quit_option : skip_quit_option
            print " > "
            response = read_input(metadata[:multiline])
            uc_response = response.upcase
            case uc_response
              when 'SKIP'
                if metadata[:required]
                  puts "Cannot skip, value required".red
                else
                  flag = true
                end
              when 'QUIT'
                return nil
              when ""
                # if a default value is defined for this parameter (i.e. the metadata[:default]
                # value is non-nil) then use that value as the value for this parameter
                if metadata[:default]
                  flag = validate_metadata_value(metadata[:default], metadata[:validation])
                  val = metadata[:default] if flag
                else
                  puts "No default value, must enter something".red
                end
              else
                flag = validate_metadata_value(response, metadata[:validation])
                puts "Value (".red + "#{response}".yellow + ") is invalid".red unless flag
                val = response if flag
            end
          end
          req_metadata_params[key] = val
        }
        req_metadata_params
      end

      def read_input(multiline = false)
        if multiline
          response = ""
          while line = STDIN.gets
            if line =~ /^$/
              break
            else
              response += line
            end
          end
          response
        else
          STDIN.gets.strip
        end
      end

      def map_keys_to_symbols(hash)
        tmp = {}
        hash.each { |key, val|
          key = key.to_sym if !key.is_a?(Symbol)
          tmp[key] = val
        }
        tmp
      end

      def set_metadata_value(key, value, md_hash = req_metadata_hash)
        md_hash_value = map_keys_to_symbols(md_hash[key])
        is_required_field = md_hash_value[:required]
        # skip any empty/nil values that aren't required (i.e. continue only if it's a required field or the field
        # is not required but the value is not empty/nil)
        return true unless is_required_field || value
        # otherwise, validate the value and, if is valid, set a corresponding
        # instance variable
        validation_str = md_hash_value[:validation]
        regex = Regexp.new(validation_str) if validation_str && !validation_str.empty?
        is_valid = false
        if value.is_a?(Array)
          # if have an array of values as input, then the input value is only valid
          # if all of the array's values themselves match the regular expression used
          # for validation (or if the regular expression was never set or was empty)
          is_valid = value.map{ |val| regex ? regex.match(value) : true }.select{ |val| val }.size == value.size
        else
          is_valid = regex ? regex.match(value) : true
        end
        if is_valid
          self.instance_variable_set(key.to_sym, value)
          true
        else
          false
        end
      end


      def set_default_metadata_value(key, md_hash = req_metadata_hash)
        md_hash_value = map_keys_to_symbols(md_hash[key])
        validation_str = md_hash_value[:validation]
        def_value = md_hash_value[:default]
        regex = Regexp.new(validation_str) if validation_str && !validation_str.empty?
        def_is_valid = regex ? regex.match(def_value) : true
        if (md_hash_value[:required] && def_value && def_is_valid)
          self.instance_variable_set(key.to_sym, def_value)
          true
        elsif !md_hash_value[:required]
          true
        else
          false
        end
      end

      def validate_metadata_value(value, validation)
        regex = Regexp.new(validation)
        if regex =~ value
          true
        else
          false
        end
      end

      def skip_quit_option
        "(" + "SKIP".white + " to skip, " + "QUIT".red + " to cancel)"
      end

      def quit_option
        "(" + "QUIT".red + " to cancel)"
      end

      def mk_call(node, policy_uuid)
        @node, @policy_uuid = node, policy_uuid
      end

      def boot_call(node, policy_uuid)
        @node, @policy_uuid = node, policy_uuid
      end

      def broker_fsm_log
        fsm_log(:state     => @current_state,
                :old_state => @final_state,
                :action    => :broker_agent_handoff,
                :method    => :broker,
                :node_uuid => @node.uuid,
                :timestamp => Time.now.to_i)
      end
    end
  end
end
