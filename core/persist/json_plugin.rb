module ProjectHanlon
  module Persist
    # Json version of {ProjectHanlon::Persist::PluginInterface}
    # used by {ProjectHanlon::Persist::Controller} when ':json' is the 'persist_mode'
    # in ProjectHanlon configuration
    class JsonPlugin < PluginInterface
      include(ProjectHanlon::Logging)
      # Closes connection if it is active
      #
      # @return [Boolean] Connection status
      #
      def teardown
        @collections = nil
      end

      # Establishes connection to the data store.
      #
      # @param hostname [String] DNS name or IP-address of host
      # @param port [Integer] Port number to use when connecting to the host
      # @param username [String] Username that will be used to authenticate to the host
      # @param password [String] Password that will be used to authenticate to the host
      # @param timeout [Integer] Connection timeout
      # @return [Boolean] Connection status
      #
      def connect(hostname, port, username, password, timeout)
        begin
          if File.exists?(json_file)
            logger.debug "Loading from existing JSON file: (#{json_file})"
            json_content = File.read(json_file)
            logger.debug "JSON content: #{json_content}"
            @collections = JSON.load json_content
            logger.debug "@collections = #{@collections}"
          else
            logger.debug "Creating empty JSON file: (#{json_file})"
            @collections = Hash.new do |hash, key| hash[key] = {} end
          end
        rescue Exception => e
          puts 'WE CAUGHT IT'
          raise e
          #           if e.message.include? 'database "' + dbname + '" does not exist'
          #             @connection = create_database(hostname, port, username, password, db
          # name, timeout)
          #           else
          #             logger.error e.message
          #             raise
        end
        !!@collections.keys
      end

      def json_file
        "#{$config.persist_dbname}.json"
      end

      def write_json
        logger.debug "Persisting to JSON file: (#{json_file})"
        begin
          File.open(json_file, 'w') {|f| f.write @collections.to_json }
          #            File.write(json_file)JSON.dump(@collections)
        rescue Exception => e
          puts 'WE CAUGHT IT'
          raise e
          #           if e.message.include? 'database "' + dbname + '" does not exist'
          #             @connection = create_database(hostname, port, username, password, db
          # name, timeout)
          #           else
          #             logger.error e.message
          #             raise
        end
      end

      # Disconnects connection
      #
      # @return [Boolean] Connection status
      #
      def disconnect
        return if not @collections
        write_json
        @collections = nil
      end

      # Checks whether the database is connected and active
      #
      # @return [Boolean] Connection status
      #
      def is_db_selected?
        !!@collections
      end

      # Returns all entries from the collection named 'collection_name'
      #
      # @param collection_name [Symbol]
      # @return [Array<Hash>]
      #
      def object_doc_get_all(collection_name)
        @collections[collection_name].values.map {|e| e[:json] }
      end

      # Returns the entry keyed by the '@uuid' of the given 'object_doc' from the collection
      # named 'collection_name'
      #
      # @param object_doc [Hash]
      # @param collection_name [Symbol]
      # @return [Hash] or nil if the object cannot be found
      #
      def object_doc_get_by_uuid(object_doc, collection_name)
        entry = @collections[collection_name][object_doc['@uuid']]
        if entry
          entry[:json]
        else
          nil
        end
      end

      # Adds or updates 'obj_document' in the collection named 'collection_name' with an incremented
      # '@version' value
      #
      # @param object_doc [Hash]
      # @param collection_name [Symbol]
      # @return [Hash] The updated doc
      #
      def object_doc_update(object_doc, collection_name)
        uuid = object_doc['@uuid']
        raise ArgumentError.new('Document has no uuid') if uuid === nil

        entries = @collections[collection_name]
        if entries === nil
          entries = Hash.new
          @collections[collection_name] = entries
        end

        entry = entries[uuid]
        old_version = object_doc['@version']
        if entry === nil
          version = 1
        else
          version = (old_version > 0 ? old_version : entry[:version]) + 1
        end
        object_doc['@version'] = version
        entries[uuid] = { :version => version, :json => object_doc }
        write_json
        object_doc
      end

      # Adds or updates multiple object documents in the collection named 'collection_name'. This will
      # increase the '@version' value of all the documents
      #
      # @param object_docs [Array<Hash>]
      # @param collection_name [Symbol]
      # @return [Array<Hash>] The updated documents
      #
      def object_doc_update_multi(object_docs, collection_name)
        object_docs.collect {|object_doc|object_doc_update(object_doc,collection_name)}
      end

      # Removes a document identified by from the '@uuid' of the given 'object_doc' from the
      # collection named 'collection_name'
      #
      # @param object_doc [Hash]
      # @param collection_name [Symbol]
      # @return [Boolean] - returns 'true' if an object was removed
      #
      def object_doc_remove(object_doc, collection_name)
        uuid = object_doc['@uuid']
        raise ArgumentError.new('Document has no uuid') if uuid === nil
        entries = @collections[collection_name]
        entries.delete(uuid) unless entries === nil
        write_json
        true
      end

      # Removes all documents from the collection named 'collection_name'
      #
      # @param collection_name [Symbol]
      # @return [Boolean] - returns 'true' if all entries were successfully removed
      #
      def object_doc_remove_all(collection_name)
        @collections.delete(collection_name)
        write_json
        true
      end
    end
  end
end
