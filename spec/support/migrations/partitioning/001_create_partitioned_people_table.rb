# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:people, partition_by: :date_of_birth) do
      String :name
      Date :date_of_birth
    end
  end
end
