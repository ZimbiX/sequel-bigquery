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
    DATABASE_SETUP = {}
      
    class Database < Sequel::Database
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
        # self.input_identifier_meth = nil
        # self.identifier_output_method = nil

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

      def disconnect_connection(c)
        puts '#disconnect_connection'
        # c.disconnect
      end

      def execute(sql, opts=OPTS)
        puts '#execute'
        log_query(sql)

        # require 'pry'; binding.pry if sql =~ /CREATE TABLE IF NOT EXISTS/i

        sql = sql.gsub(/\sdefault \S+/i) do
          warn_default_removal(sql)
          ''
        end

        if sql =~ /^update/i && sql !~ / where /i
          warn("Warning: Appended 'where 1 = 1' to query since BigQuery requires UPDATE statements to include a WHERE clause")
          sql = sql + ' where 1 = 1'
        end

        if sql =~ /^begin/i
          warn_transaction
          @sql_buffering = true
        end

        if @sql_buffering
          @sql_buffer << sql
          if sql =~ /^commit/i
            warn("Warning: Will now execute entire buffered transaction:\n" + @sql_buffer.join("\n"))
          else
            return []
          end
        end

        synchronize(opts[:server]) do |conn|
          begin
            results = log_connection_yield(sql, conn) do
              sql_to_execute = @sql_buffer.any? ? @sql_buffer.join("\n") : sql
              conn.query(sql_to_execute)
              # raw_result = conn.query(sql_to_execute)
              # BQResult.new(raw_result)
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
          end
        end
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

      # def supports_transactional_ddl?
      #   false
      # end
      
      # def execute_dui(sql, opts=OPTS)
      # end

      # def execute_dui(sql, opts=OPTS)
      #   # require 'pry'; binding.pry
      #   synchronize(opts[:server]) do |conn|
      #     begin
      #       log_connection_yield(sql, conn){conn.do(sql)}
      #     # TODO:
      #     # rescue ::ODBC::Error, ArgumentError => e
      #     rescue ArgumentError => e
      #       raise_error(e)
      #     end
      #   end
      # end

      private
      
      def adapter_initialize
        puts '#adapter_initialize'
        self.extension(:identifier_mangling)
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

      def schema_parse_table(table_name, opts)
        logger.debug(Paint['schema_parse_table', :red, :bold])
        # require 'pry'; binding.pry
        @bigquery.datasets.map do |dataset|
          [
            dataset.dataset_id,
            {}
          ]
        end
      end

      def disconnect_error?(e, opts)
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
        warn('Warning: Transaction detected. This only supported on BigQuery in a script or session. Commencing buffering to run the whole transaction at once as a script upon commit. Note that no result data is returned while the transaction is open.')
      end
    end

    # class BQResult < SimpleDelegator

    # end
    
    class Dataset < Sequel::Dataset
      def fetch_rows(sql)
        puts '#fetch_rows'
        # execute(sql) do |s|
        #   i = -1
        #   cols = s.columns(true).map{|c| [output_identifier(c.name), c.type, i+=1]}
        #   columns = cols.map{|c| c[0]}
        #   self.columns = columns
        #   s.each do |row|
        #     hash = {}
        #     cols.each{|n,t,j| hash[n] = convert_odbc_value(row[j], t)}
        #     yield hash
        #   end
        # end
        # self

        execute(sql) do |bq_result|
          self.columns = bq_result.fields.map { |field| field.name.to_sym }
          bq_result.each do |row|
            yield row
          end
        end

        # execute(sql).each do |row|
        #   yield row
        # end
        self
      end

      # def columns
      #   fields.map { |field| field.name.to_sym }
      # end
      
      private

      # def convert_odbc_value(v, t)
      #   # When fetching a result set, the Ruby ODBC driver converts all ODBC
      #   # SQL types to an equivalent Ruby type; with the exception of
      #   # SQL_TYPE_DATE, SQL_TYPE_TIME and SQL_TYPE_TIMESTAMP.
      #   #
      #   # The conversions below are consistent with the mappings in
      #   # ODBCColumn#mapSqlTypeToGenericType and Column#klass.
      #   case v
      #   when ::ODBC::TimeStamp
      #     db.to_application_timestamp([v.year, v.month, v.day, v.hour, v.minute, v.second, v.fraction])
      #   when ::ODBC::Time
      #     Sequel::SQLTime.create(v.hour, v.minute, v.second)
      #   when ::ODBC::Date
      #     Date.new(v.year, v.month, v.day)
      #   else
      #     if t == ::ODBC::SQL_BIT
      #       v == 1
      #     else
      #       v
      #     end
      #   end
      # end

      def literal_time(v)
        "'#{v.iso8601}'"
      end

      # def literal_date(v)
      #   v.strftime("{d '%Y-%m-%d'}")
      # end
      
      def literal_false
        'false'
      end
      
      def literal_true
        'true'
      end
    end
  end
end
