require "erb"

# Root ProjectHanlon namespace
module ProjectHanlon
  module ModelTemplate
    # Root Model object
    # @abstract
    class Coreos < ProjectHanlon::ModelTemplate::Base
      include(ProjectHanlon::Logging)

      # Assigned image
      attr_accessor :image_uuid
      # Metadata
      attr_accessor :hostname
      attr_accessor :domainname
      # Compatible Image Prefix
      attr_accessor :image_prefix

      def initialize(hash)
        super(hash)
        # Static config
        @hidden      = true
        @template = :linux_deploy
        @name = "coreos_generic"
        @description = "CoreOS Generic Model"
        # Metadata vars
        @hostname_prefix = nil
        # State / must have a starting state
        @current_state = :init
        # Image UUID
        @image_uuid = true
        # Image prefix we can attach
        @image_prefix = "os"
        # Enable agent brokers for this model
        @broker_plugin = :agent
        # Default install disk
        @install_disk = "/dev/sda"
        # Default: no cloud config
        @cloud_config = nil
        @final_state = :os_complete
        from_hash(hash) unless hash == nil
        @req_metadata_hash = {
          "@hostname_prefix" => {
            :default     => "node",
            :example     => "node",
            :validation  => '^[a-zA-Z0-9][a-zA-Z0-9\-]*$',
            :required    => true,
            :description => "node hostname prefix (will append node number)"
          },
          "@domainname" => {
            :default     => "localdomain",
            :example     => "example.com",
            :validation  => '^[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9](\.[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9])*$',
            :required    => true,
            :description => "local domain name (will be used in /etc/hosts file)"
          }
        }
        @opt_metadata_hash = {
          "@install_disk" => { 
            :default      => "/dev/sda",
            :example      => "/dev/sda",
            :validation   => '',
            :required     => false,
            :description  => "The Core OS target disk"
          },
          "@cloud_config" => { 
            :default      => "",
            :example      => "",
            :validation   => '',
            :required     => false,
            :description  => "A yaml containing CoreOS cloud config options"
          }
        }
      end

      def callback
        {
          "postinstall" => :postinstall_call,
          "cloud-config.sh" => :cloud_config_call,
        }
      end

      def broker_agent_handoff
        logger.debug "Broker agent called for: #{@broker.name}"
        if @node_ip
          options = {
            :username  => "root",
            :password  => @root_password,
            :metadata  => node_metadata,
            :uuid  => @node.uuid,
            :ipaddress => @node_ip,
          }
          @current_state = @broker.agent_hand_off(options)
        else
          logger.error "Node IP address isn't known"
          @current_state = :broker_fail
        end
        broker_fsm_log
      end
      
      def cloud_config_call
        return generate_cloud_config(@policy_uuid)
      end

      def postinstall_call
        @arg = @args_array.shift
        case @arg
          when "send_ips"
            # Grab IP string
            @ip_string = @args_array.shift
            logger.debug "Node IP String: #{@ip_string}"
            @node_ip = @ip_string if @ip_string =~ /\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/
            return
          when "complete"
            fsm_action(:install_complete, :os_complete)
            return
          when "install_fail"
            fsm_action(:post_error, :os_complete)
            return
          else
            fsm_action(@arg.to_sym, :postinstall)
            return
        end
      end

      # Defines our FSM for this model
      #  For state => {action => state, ..}
      def fsm_tree
        {
          :init => {
            :mk_call       => :init,
            :boot_call     => :init,
            :timeout       => :timeout_error,
            :error         => :error_catch,
            :else          => :init,
            :install_complete => :os_complete 
          },
          :postinstall => {
            :mk_call            => :postinstall,
            :boot_call          => :postinstall,
            :os_boot            => :postinstall,
            :os_final           => :os_complete,
            :post_error         => :error_catch,
            :post_timeout       => :timeout_error,
            :error              => :error_catch,
            :else               => :postinstall
          },
          :os_complete => {
            :mk_call   => :os_complete,
            :boot_call => :os_complete,
            :else      => :os_complete,
            :reset     => :init
          },
          :timeout_error => {
            :mk_call   => :timeout_error,
            :boot_call => :timeout_error,
            :else      => :timeout_error,
            :reset     => :init
          },
          :error_catch => {
            :mk_call   => :error_catch,
            :boot_call => :error_catch,
            :else      => :error_catch,
            :reset     => :init
          },
        }
      end

      def mk_call(node, policy_uuid)
        super(node, policy_uuid)
        case @current_state
          # We need to reboot
          when :init, :preinstall, :postinstall, :os_validate, :os_complete, :broker_check, :broker_fail, :broker_success
            ret = [:reboot, {}]
          when :timeout_error, :error_catch
            ret = [:acknowledge, {}]
          else
            ret = [:acknowledge, {}]
        end
        fsm_action(:mk_call, :mk_call)
        ret
      end

      def boot_call(node, policy_uuid)
        super(node, policy_uuid)
        case @current_state
          when :init, :preinstall
            @result = "Starting CoreOS model install"
            ret = start_install(node, policy_uuid)
          when :postinstall, :os_complete, :broker_check, :broker_fail, :broker_success, :complete_no_broker
            ret = local_boot(node)
          when :timeout_error, :error_catch
            engine = ProjectHanlon::Engine.instance
            ret = engine.default_mk_boot(node.uuid)
          else
            engine = ProjectHanlon::Engine.instance
            ret = engine.default_mk_boot(node.uuid)
        end
        fsm_action(:boot_call, :boot_call)
        ret
      end

      # ERB.result(binding) is failing in Ruby 1.9.2 and 1.9.3 so template is processed in the def block.
      def template_filepath(filename)
        filepath = File.join(File.dirname(__FILE__), "coreos/#{filename}.erb")
      end

      def os_boot_script(policy_uuid)
        @result = "Replied with os boot script"
        filepath = template_filepath('os_boot')
        ERB.new(File.read(filepath)).result(binding)
      end

      def os_complete_script(node)
        @result = "Replied with os complete script"
        filepath = template_filepath('os_complete')
        ERB.new(File.read(filepath)).result(binding)
      end

      def start_install(node, policy_uuid)
        filepath = template_filepath('boot_install')
        ERB.new(File.read(filepath)).result(binding)
      end

      def local_boot(node)
        filepath = template_filepath('boot_local')
        ERB.new(File.read(filepath)).result(binding)
      end

      def kernel_args(policy_uuid)
        filepath = template_filepath('kernel_args')
        ERB.new(File.read(filepath)).result(binding)
      end

      def hostname
        "#{@hostname_prefix}#{@counter.to_s}"
      end
      
      def install_disk
        @install_disk
      end

      def cloud_config_yaml
        if @cloud_config
          @cloud_config.to_yaml
        else
          ""
        end
      end

      def kernel_path
        "coreos/vmlinuz"
      end

      def initrd_path
        "coreos/cpio.gz"
      end
      
      # TODO: make optional
      # This will only affect the boot for install. It is helpful to debug errors
      def autologin_kernel_args
        "console=tty0 console=ttyS0 coreos.autologin"
      end

      def config
        ProjectHanlon.config
      end
      
      def generate_cloud_config(policy_uuid)
        filepath = template_filepath('cloud-config')
        ERB.new(File.read(filepath)).result(binding)
      end

    end
  end
end
