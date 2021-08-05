# frozen-string-literal: true

require 'google/cloud/bigquery'
# require 'sequel/postgres'

module Sequel
  module Bigquery
    # Contains procs keyed on subadapter type that extend the
    # given database object so it supports the correct database type.
    DATABASE_SETUP = {}
      
    class Database < Sequel::Database
      set_adapter_scheme :bigquery

      def initialize(*args, **kawrgs)
        @orig_opts = kawrgs.fetch(:orig_opts)
        super
      end

      def connect(*_args)
        # self.input_identifier_meth = nil
        # self.identifier_output_method = nil

        config = @orig_opts.dup
        config.delete(:adapter)
        bq_dataset_name = config.delete(:dataset)
        # require 'pry'; binding.pry
        @bigquery = Google::Cloud::Bigquery.new(config)
        # require 'pry'; binding.pry
        @bigquery.dataset(bq_dataset_name)
      end

      def disconnect_connection(c)
        c.disconnect
      end

      def execute(sql, opts=OPTS)
        synchronize(opts[:server]) do |conn|
          begin
            r = log_connection_yield(sql, conn){conn.query(sql)}
            if block_given?
              yield(r)
            else
              r
            end
          # TODO
          # rescue ::ODBC::Error, ArgumentError => e
          rescue ArgumentError => e
            raise_error(e)
          end
        end
      end
      
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
    end
    
    class Dataset < Sequel::Dataset
      def fetch_rows(sql)
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

        execute(sql).each do |row|
          yield row
        end
        self
      end
      
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

      def default_timestamp_format
        "{ts '%Y-%m-%d %H:%M:%S'}"
      end

      def literal_date(v)
        v.strftime("{d '%Y-%m-%d'}")
      end
      
      def literal_false
        '0'
      end
      
      def literal_true
        '1'
      end
    end
  end
end
