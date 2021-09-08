# frozen-string-literal: true

require 'delegate'
require 'time'

require 'google/cloud/bigquery'
require 'paint'
require 'sequel'

module Sequel
  module Bigquery
    # Contains procs keyed on subadapter type that extend the
    # given database object so it supports the correct database type.
    DATABASE_SETUP = {}.freeze

    class Database < Sequel::Database # rubocop:disable Metrics/ClassLength
      set_adapter_scheme :bigquery

      def initialize(*args, **kawrgs)
        puts '.new'
        @orig_opts = kawrgs.fetch(:orig_opts)
        @sql_buffer = []
        @sql_buffering = false
        super
      end

      def connect(*_args)
        puts '#connect'
        config = @orig_opts.dup
        config.delete(:adapter)
        config.delete(:logger)
        bq_dataset_name = config.delete(:dataset) || config.delete(:database)
        @bigquery = Google::Cloud::Bigquery.new(config)
        # ObjectSpace.each_object(HTTPClient).each { |c| c.debug_dev = STDOUT }
        @bigquery.dataset(bq_dataset_name) || begin
          @loggers[0].debug('BigQuery dataset %s does not exist; creating it' % bq_dataset_name)
          @bigquery.create_dataset(bq_dataset_name)
        end
          .tap { puts '#connect end' }
      end

      def disconnect_connection(_c) # rubocop:disable Naming/MethodParameterName
        puts '#disconnect_connection'
        # c.disconnect
      end

      def execute(sql, opts = OPTS) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        puts '#execute'
        log_query(sql)

        # require 'pry'; binding.pry if sql =~ /CREATE TABLE IF NOT EXISTS/i

        sql = sql.gsub(/\sdefault \S+/i) do
          warn_default_removal(sql)
          ''
        end

        if sql =~ /^update/i && sql !~ / where /i
          warn("Warning: Appended 'where 1 = 1' to query since BigQuery requires UPDATE statements to include a WHERE clause")
          sql += ' where 1 = 1'
        end

        if /^begin/i.match?(sql)
          warn_transaction
          @sql_buffering = true
        end

        if @sql_buffering
          @sql_buffer << sql
          return [] unless /^commit/i.match?(sql)
          warn("Warning: Will now execute entire buffered transaction:\n" + @sql_buffer.join("\n"))
        end

        synchronize(opts[:server]) do |conn|
          results = log_connection_yield(sql, conn) do
            sql_to_execute = @sql_buffer.any? ? @sql_buffer.join("\n") : sql
            conn.query(sql_to_execute)
          end
          require 'amazing_print'
          ap results
          if block_given?
            yield results
          else
            results
          end
        # TODO
        # rescue ::ODBC::Error, ArgumentError => e
        rescue Google::Cloud::InvalidArgumentError, ArgumentError => e
          raise_error(e)
        end # rubocop:disable Style/MultilineBlockChain
          .tap do
            @sql_buffer = []
            @sql_buffering = false
          end
      end

      def supports_create_table_if_not_exists?
        true
      end

      def type_literal_generic_string(column)
        if column[:size]
          "string(#{column[:size]})"
        else
          :string
        end
      end

      private

      def adapter_initialize
        puts '#adapter_initialize'
        extension(:identifier_mangling)
        self.identifier_input_method = nil
        self.quote_identifiers = false
      end

      def connection_execute_method
        :query
      end

      def database_error_classes
        # [::ODBC::Error]
        # TODO
      end

      def dataset_class_default
        Dataset
      end

      def schema_parse_table(_table_name, _opts)
        logger.debug(Paint['schema_parse_table', :red, :bold])
        # require 'pry'; binding.pry
        @bigquery.datasets.map do |dataset|
          [
            dataset.dataset_id,
            {},
          ]
        end
      end

      def disconnect_error?(e, opts) # rubocop:disable Lint/UselessMethodDefinition, Naming/MethodParameterName
        # super || (e.is_a?(::ODBC::Error) && /\A08S01/.match(e.message))
        super
      end

      # Padded to horizontally align with post-execution log message which includes the execution time
      def log_query(sql)
        pad = '                                                                '
        puts Paint[pad + sql, :cyan, :bold]
        # @loggers[0]&.debug('            ' + sql)
      end

      def warn(msg)
        @loggers[0].warn(Paint[msg, '#FFA500', :bold])
      end

      def warn_default_removal(sql)
        warn("Warning: Default removed from below query as it's not supported on BigQuery:\n%s" % sql)
      end

      def warn_transaction
        warn(
          'Warning: Transaction detected. This only supported on BigQuery in a script or session. '\
          'Commencing buffering to run the whole transaction at once as a script upon commit. ' \
          'Note that no result data is returned while the transaction is open.',
        )
      end
    end

    class Dataset < Sequel::Dataset
      def fetch_rows(sql, &block)
        puts '#fetch_rows'

        execute(sql) do |bq_result|
          self.columns = bq_result.fields.map { |field| field.name.to_sym }
          bq_result.each(&block)
        end

        self
      end

      private

      def literal_time(v) # rubocop:disable Naming/MethodParameterName
        "'#{v.iso8601}'"
      end

      def literal_false
        'false'
      end

      def literal_true
        'true'
      end
    end
  end
end
