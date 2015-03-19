
module ProjectHanlon
  module Persist
    # Persistence Controller for ProjectHanlon
    class Controller
      include(ProjectHanlon::Logging)

      attr_accessor :database
      attr_accessor :config

      # Initializes the controller and configures the correct '@database' object based on the 'persist_mode' specified in the config
      def initialize()
        logger.debug "Initializing object"
        # copy config into instance
        #
        # @todo danielp 2013-03-13: well, this seems less helpful now that
        # config has a sane global accessor, but whatever.  Keeping this
        # reduces code churn right this second.
        #@config = ProjectHanlon.config
        @config = $config
        # init correct database object
        if (config.persist_mode == :mongo)
          logger.debug "Using Mongo plugin"
          # ToDo::Sankar::Clean junk code
          #require "project_hanlon/persist/mongo_plugin" unless ProjectHanlon::Persist.const_defined?(:MongoPlugin)
          require "persist/mongo_plugin" unless ProjectHanlon::Persist.const_defined?(:MongoPlugin)
          @database = ProjectHanlon::Persist::MongoPlugin.new
        elsif (config.persist_mode == :postgres)
          logger.debug "Using Postgres plugin"
          # ToDo::Sankar::Clean junk code
          #require "project_hanlon/persist/postgres_plugin" unless ProjectHanlon::Persist.const_defined?(:PostgresPlugin)
          require "persist/postgres_plugin" unless ProjectHanlon::Persist.const_defined?(:PostgresPlugin)
          @database = ProjectHanlon::Persist::PostgresPlugin.new
        elsif (config.persist_mode == :memory)
          logger.debug "Using in-memory plugin"
          # ToDo::Sankar::Clean junk code
          #require "project_hanlon/persist/memory_plugin" unless ProjectHanlon::Persist.const_defined?(:MemoryPlugin)
          require "persist/memory_plugin" unless ProjectHanlon::Persist.const_defined?(:MemoryPlugin)
          @database = ProjectHanlon::Persist::MemoryPlugin.new
        elsif (config.persist_mode == :yaml)
          logger.debug "Using yaml plugin"
          #require "project_hanlon/persist/memory_plugin" unless ProjectHanlon::Persist.const_defined?(:YamlPlugin)
          require "persist/yaml_plugin" unless ProjectHanlon::Persist.const_defined?(:YamlPlugin)
          @database = ProjectHanlon::Persist::YamlPlugin.new
        else
          logger.error "Invalid Database plugin(#{config.persist_mode})"
          return;
        end
        check_connection
      end

      # This is where all connection teardown is started. Calls the '@database.teardown'
      def teardown
        logger.debug "Connection teardown"
        @database.teardown
      end

      # Returns true|false whether DB/Connection is open
      # Use this when you want to check but not reconnect
      # @return [true, false]
      def is_connected?
        logger.debug "Checking if DB is selected(#{@database.is_db_selected?})"
        @database.is_db_selected?
      end

      # Checks and reopens closed DB/Connection
      # Use this to check connection after trying to make sure it is open
      # @return [true, false]
      def check_connection
        logger.debug "Checking connection (#{is_connected?})"
        is_connected? || connect_database
        # return connection status
        is_connected?
      end

      # Connect to database using ProjectHanlon::Persist::Database::Plugin loaded
      def connect_database
        logger.debug "Connecting to database(#{@config.persist_username}#{@config.persist_host}:#{@config.persist_port}) with timeout(#{@config.persist_timeout})"
        @database.connect(@config.persist_host, @config.persist_port, @config.persist_username, @config.persist_password, @config.persist_timeout)
      end




      # Get all object documents from database collection: 'collection'
      # @param collection [Symbol] - name of the collection
      # @return [Array] - Array containing the
      def object_hash_get_all(collection)
        logger.debug "Retrieving object documents from collection(#{collection})"
        @database.object_doc_get_all(collection)
      end

      def object_hash_get_by_uuid(object_doc, collection)
        logger.debug "Retrieving object document from collection(#{collection}) by uuid(#{object_doc['@uuid']})"
        @database.object_doc_get_by_uuid(object_doc, collection)
      end

      # Add/update object document to the collection: 'collection'
      # @param object_doc [Hash]
      # @param collection [Symbol]
      # @return [Hash]
      def object_hash_update(object_doc, collection)
        logger.debug "Updating object document from collection(#{collection}) by uuid(#{object_doc['@uuid']})"
        @database.object_doc_update(object_doc, collection)
      end

      def object_hash_update_multi(object_doc_array, collection)
        logger.debug "Updating object documents from collection(#{collection})"
        @database.object_doc_update_multi(object_doc_array, collection)
      end

      # Remove object document with UUID from collection: 'collection' completely
      # @param object_doc [Hash]
      # @param collection [Symbol]
      # @return [true, false]
      def object_hash_remove(object_doc, collection)
        logger.debug "Removing object document from collection(#{collection}) by uuid(#{object_doc['@uuid']})"
        @database.object_doc_remove(object_doc, collection) || false
      end

      def object_hash_remove_all(collection)
        logger.debug "Removing all object documents from collection(#{collection})"
        @database.object_doc_remove_all(collection)
      end
    end
  end
end
