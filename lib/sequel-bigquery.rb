# frozen-string-literal: true

require 'delegate'
require 'time'

require 'google/cloud/bigquery'
require 'amazing_print'
require 'paint'
require 'sequel'

module Sequel
  module Bigquery
    # Contains procs keyed on subadapter type that extend the
    # given database object so it supports the correct database type.
    DATABASE_SETUP = {}.freeze

    class Database < Sequel::Database # rubocop:disable Metrics/ClassLength
      set_adapter_scheme :bigquery

      def initialize(opts)
        @bigquery_config = opts.fetch(:orig_opts)
        @sql_buffer = []
        @sql_buffering = false
        super
      end

      def connect(*_args)
        log_each(:debug, '#connect')
        get_or_create_bigquery_dataset
          .tap { log_each(:debug, '#connect end') }
      end

      def bigquery
        # ObjectSpace.each_object(HTTPClient).each { |c| c.debug_dev = STDOUT }
        @bigquery ||= Google::Cloud::Bigquery.new(**google_cloud_bigquery_gem_config)
      end

      def disconnect_connection(_c)
        log_each(:debug, '#disconnect_connection')
        # c.disconnect
      end

      def drop_datasets(*dataset_names_to_drop)
        dataset_names_to_drop.each do |dataset_name_to_drop|
          log_each(:debug, "Dropping dataset #{dataset_name_to_drop.inspect}")
          dataset_to_drop = bigquery.dataset(dataset_name_to_drop)
          next unless dataset_to_drop
          dataset_to_drop.tables.each(&:delete)
          dataset_to_drop.delete
        end
      end
      alias drop_dataset drop_datasets

      def execute(sql, opts = OPTS) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        log_each(:debug, '#execute')
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

        sql_to_execute = @sql_buffer.any? ? @sql_buffer.join("\n") : sql

        synchronize(opts[:server]) do |conn|
          results = log_connection_yield(sql, conn) do
            conn.query(sql_to_execute)
          end
          log_each(:debug, results.awesome_inspect)
          if block_given?
            yield results
          else
            results
          end
        rescue Google::Cloud::InvalidArgumentError, Google::Cloud::PermissionDeniedError => e
          if e.message.include?('too many table update operations for this table')
            warn('Triggered rate limit of table update operations for this table. For more information, see https://cloud.google.com/bigquery/docs/troubleshoot-quotas')
            if retryable_query?(sql_to_execute)
              warn('Detected retryable query - re-running query after a 1 second sleep')
              sleep 1
              retry
            else
              log_each(:error, "Query not detected as retryable; can't automatically recover from being rate-limited")
            end
          end
          raise_error(e)
        rescue ArgumentError => e
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

      def type_literal_generic_float(_column)
        :float64
      end

      private

      attr_reader :bigquery_config

      def google_cloud_bigquery_gem_config
        bigquery_config.dup.tap do |config|
          %i[
            adapter
            database
            dataset
            location
            logger
          ].each do |option|
            config.delete(option)
          end
        end
      end

      def get_or_create_bigquery_dataset # rubocop:disable Naming/AccessorMethodName
        bigquery.dataset(bigquery_dataset_name) || begin
          log_each(:debug, 'BigQuery dataset %s does not exist; creating it' % bigquery_dataset_name)
          bigquery.create_dataset(bigquery_dataset_name, location: bigquery_config[:location])
        end
      end

      def bigquery_dataset_name
        bigquery_config[:dataset] || bigquery_config[:database] || (raise ArgumentError, 'BigQuery dataset must be specified')
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
        log_each(:debug, Paint['schema_parse_table', :red, :bold])
        # require 'pry'; binding.pry
        bigquery.datasets.map do |dataset|
          [
            dataset.dataset_id,
            {},
          ]
        end
      end

      def disconnect_error?(e, opts) # rubocop:disable Lint/UselessMethodDefinition
        # super || (e.is_a?(::ODBC::Error) && /\A08S01/.match(e.message))
        super
      end

      # Padded to horizontally align with post-execution log message which includes the execution time
      def log_query(sql)
        pad = ' ' * 12
        log_each(:debug, Paint[pad + sql, :cyan, :bold])
      end

      def warn(msg)
        log_each(:warn, Paint[msg, '#FFA500', :bold])
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

      # SQL for creating a table with BigQuery specific options
      def create_table_sql(name, generator, options)
        "#{super}#{create_table_suffix_sql(name, options)}"
      end

      # Handle BigQuery specific table extensions (i.e. partitioning)
      def create_table_suffix_sql(_name, options)
        sql = +''

        if (partition_by = options[:partition_by])
          sql << " PARTITION BY #{literal(Array(partition_by))}"
        end

        sql
      end

      def supports_combining_alter_table_ops?
        true
      end

      def retryable_query?(sql)
        single_statement_query?(sql) && alter_table_query?(sql)
      end

      def single_statement_query?(sql)
        !sql.rstrip.chomp(';').include?(';')
      end

      def alter_table_query?(sql)
        sql.match?(/\Aalter table /i)
      end
    end

    class Dataset < Sequel::Dataset
      def fetch_rows(sql, &block)
        db.send(:log_each, :debug, '#fetch_rows')

        execute(sql) do |bq_result|
          self.columns = bq_result.fields.map { |field| field.name.to_sym }
          bq_result.each(&block)
        end

        self
      end

      private

      def literal_time(v)
        "'#{v.iso8601}'"
      end

      def literal_false
        'false'
      end

      def literal_true
        'true'
      end

      # Like MySQL, BigQuery uses the nonstandard ` (backtick) for quoting identifiers.
      def quoted_identifier_append(sql, c)
        sql << ('`%s`' % c)
      end

      def input_identifier(v)
        v.to_s
      end
    end
  end
end
