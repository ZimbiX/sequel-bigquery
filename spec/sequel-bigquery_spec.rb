# frozen-string-literal: true

require 'spec_helper'

Sequel.extension :migration

RSpec.describe Sequel::Bigquery do # rubocop:disable RSpec/FilePath
  let(:db) do
    Sequel.connect(
      adapter: :bigquery,
      project: project_name,
      database: isolated_dataset_name(dataset_name),
      location: location,
      logger: Logger.new(STDOUT),
    )
  end
  let(:project_name) { 'greensync-dex-dev' }
  let(:dataset_name) { 'sequel_bigquery_gem' }
  let(:bigquery) { Google::Cloud::Bigquery.new(project: project_name) }
  let(:dataset) { bigquery.dataset(isolated_dataset_name(dataset_name)) }
  let(:location) { nil }
  let(:migrations_dir) { 'spec/support/migrations/general' }

  def recreate_dataset(name = dataset_name)
    delete_dataset(name)
    create_dataset(name)
  end

  def delete_dataset(name = dataset_name)
    puts "Deleting dataset '#{isolated_dataset_name(name)}'..."
    dataset_to_drop = bigquery.dataset(isolated_dataset_name(name))
    return unless dataset_to_drop

    dataset_to_drop.tables.each(&:delete)
    dataset_to_drop.delete
  end

  def create_dataset(name = dataset_name)
    puts "Creating dataset '#{isolated_dataset_name(name)}'..."
    bigquery.create_dataset(isolated_dataset_name(name))
  rescue Google::Cloud::AlreadyExistsError
    # cool
  end

  def table(name)
    dataset.table(name)
  end

  def isolated_dataset_name(name)
    [
      name,
      ENV['GITHUB_USERNAME'],
      ENV['BUILDKITE_BUILD_NUMBER'],
      ENV['TEST_ENV_NUMBER'],
    ].compact.join('_')
  end

  it 'can connect' do
    expect(db).to be_a(Sequel::Bigquery::Database)
  end

  describe 'with a provided location' do
    let(:location) { 'australia-southeast2' }
    let(:dataset) { instance_double(Google::Cloud::Bigquery::Dataset) }
    let(:bigquery_project) { instance_double(Google::Cloud::Bigquery::Project, dataset: nil) }

    before do
      allow(Google::Cloud::Bigquery).to receive(:new).and_return(bigquery_project)
      allow(bigquery_project).to receive(:create_dataset).and_return(dataset)
    end

    it 'can be targetted to a specific datacenter location' do
      db

      expect(bigquery_project).to have_received(:create_dataset).with(anything, hash_including(location: 'australia-southeast2'))
    end
  end

  describe 'migrating' do
    before do
      recreate_dataset
    end

    it 'can migrate' do
      expect(table('schema_info')).to be_nil
      expect(table('people')).to be_nil
      Sequel::Migrator.run(db, migrations_dir)
      expect(table('schema_info')).not_to be_nil
      expect(table('people')).not_to be_nil
    end
  end

  describe 'reading/writing rows' do
    before do
      delete_dataset
      Sequel::Migrator.run(db, migrations_dir)
    end

    let(:person) do
      {
        name: 'Reginald',
        age: 27,
        is_developer: true,
        last_skied_at: last_skied_at,
        date_of_birth: Date.new(1994, 1, 31),
        height_m: 1.870672173,
        distance_from_sun_million_km: 149.22,
      }
    end
    let(:last_skied_at) { Time.new(2016, 8, 21, 16, 0, 0, '+08:00') }

    it 'can read back an inserted row' do # rubocop:disable RSpec/ExampleLength
      db[:people].truncate
      db[:people].insert(person)
      result = db[:people].where(name: 'Reginald').all
      expect(result).to eq([
        person.merge(last_skied_at: last_skied_at.getlocal),
      ])
    end
  end

  describe 'dropping datasets' do
    let(:second_dataset_name) { 'another_test_dataset' }

    before do
      delete_dataset
      Sequel::Migrator.run(db, migrations_dir)
      recreate_dataset(second_dataset_name)
    end

    it 'can drop a dataset' do
      db.drop_dataset(isolated_dataset_name(dataset_name))

      expect(bigquery.datasets).not_to include(dataset_name)
    end

    it 'can drop multiple datasets' do # rubocop:disable RSpec/ExampleLength
      db.drop_datasets(
        isolated_dataset_name(dataset_name),
        isolated_dataset_name(second_dataset_name),
      )

      expect(bigquery.datasets).not_to include(
        isolated_dataset_name(dataset_name),
        isolated_dataset_name(second_dataset_name),
      )
    end

    it 'ignores non-existent datasets' do
      expect { db.drop_dataset('some-non-existent-dataset') }.not_to raise_error
    end
  end

  describe 'partitioning tables' do
    let(:migrations_dir) { 'spec/support/migrations/partitioning' }
    let(:expected_sql) { 'CREATE TABLE `partitioned_people` (`name` string, `date_of_birth` date) PARTITION BY (`date_of_birth`)' }

    before do
      recreate_dataset

      allow(Google::Cloud::Bigquery).to receive(:new).and_return(bigquery)
      allow(bigquery).to receive(:dataset).and_return(dataset)
      allow(dataset).to receive(:query).and_call_original

      Sequel::Migrator.run(db, migrations_dir)
    end

    it 'supports partitioning arguments' do
      expect(dataset).to have_received(:query).with(expected_sql, session_id: anything)
    end
  end

  describe 'alter table migration' do
    let(:migrations_dir) { 'spec/support/migrations/alter_table' }
    let(:expected_sql) do
      'ALTER TABLE `alter_people` '\
        'ADD COLUMN `col1` string, '\
        'ADD COLUMN `col2` string, '\
        'ADD COLUMN `col3` string, '\
        'ADD COLUMN `col4` string, '\
        'ADD COLUMN `col5` string, '\
        'ADD COLUMN `col6` string, '\
        'ADD COLUMN `col7` string, '\
        'ADD COLUMN `col8` string, '\
        'ADD COLUMN `col9` string, '\
        'ADD COLUMN `col10` string, '\
        'ADD COLUMN `col11` string, '\
        'ADD COLUMN `col12` string'
    end

    before do
      recreate_dataset

      allow(Google::Cloud::Bigquery).to receive(:new).and_return(bigquery)
      allow(bigquery).to receive(:dataset).and_return(dataset)
      allow(dataset).to receive(:query).and_call_original

      Sequel::Migrator.run(db, migrations_dir)
    end

    it 'combines queries into one alter table statement' do
      expect(dataset).to have_received(:query).with(expected_sql, session_id: anything)
    end
  end

  describe 'alter table rate limits' do
    let(:table_name) { "alter_table_rate_limits_test_#{run_id}" }
    let(:run_id) { (Time.now.to_f * 1000).to_i }
    # This set of ALTER TABLE queries are joined in order to hopefully execute everything quickly and trigger the rate-limit. Not all of the columns will get added
    let(:create_table_and_trigger_rate_limit_queries_joined) do
      [
        "CREATE TABLE `#{table_name}` (`col_initial` string)",
        (0..30).map do |i|
          "ALTER TABLE `#{table_name}` ADD COLUMN `col_#{i}` string"
        end,
        'SELECT 1',
      ].join('; ')
    end
    let(:query_to_add_column_once_rate_limited) do
      "ALTER TABLE `#{table_name}` ADD COLUMN `col_added_once_rate_limited` string"
    end

    before do
      recreate_dataset

      allow(Google::Cloud::Bigquery).to receive(:new).and_return(bigquery)
      allow(bigquery).to receive(:dataset).and_return(dataset)
    end

    def directly_create_table_and_trigger_rate_limit
      dataset.query(create_table_and_trigger_rate_limit_queries_joined)
    end

    context "when executing more schema update queries than BigQuery's rate-limit" do
      # The resulting exception could be either of these:

      # Google::Cloud::PermissionDeniedError:
      #   Exceeded rate limits: too many table update operations for this table. For more information, see https://cloud.google.com/bigquery/docs/troubleshoot-quotas

      # Sequel::DatabaseError:
      #   Google::Cloud::InvalidArgumentError: invalidQuery: Exceeded rate limits: too many table update operations for this table. For more information, see https://cloud.google.com/bigquery/troubleshooting-errors at [1:285]

      it 'successfully executes, retrying if necessary' do
        expect do
          directly_create_table_and_trigger_rate_limit
        end.to raise_error(Google::Cloud::Error, /too many table update operations for this table/)
        expect { db.execute(query_to_add_column_once_rate_limited) }.not_to raise_error
        expect(db[table_name.to_sym].columns).to include(:col_added_once_rate_limited)
      end
    end
  end

  describe 'using a standard transaction across multiple queries' do
    before do
      recreate_dataset
      db.execute('create table books (name string)')
    end

    it 'can commit' do
      db.transaction do
        db[:books].insert(name: 'The Name of the Wind')
      end
      expect(db[:books].all).to eq([{ name: 'The Name of the Wind' }])
    end

    it 'can rollback' do
      db.transaction do
        db[:books].insert(name: 'The Name of the Wind')
        raise Sequel::Rollback
      end
      expect(db[:books].all).to eq([])
    end
  end

  describe 'using Sequel::Model' do
    before do
      recreate_dataset
      db.execute('create table books (name string)')
    end

    let(:book_model_class) { Sequel::Model(db[:books]) }
    let(:book) { book_model_class.new(name: 'The Name of the Wind') }

    it 'can define and instantiate a Sequel model' do
      expect(book.name).to eq('The Name of the Wind')
    end

    xit 'can save and load a Sequel model' do
      book.save
      expect(book_model_class.all).to eq([book])
    end
  end
end
