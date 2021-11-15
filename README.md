# sequel-bigquery

[![Gem Version](https://badge.fury.io/rb/sequel-bigquery.svg)](https://rubygems.org/gems/sequel-bigquery)

A Sequel adapter for [Google's BigQuery](https://cloud.google.com/bigquery).

This gem was created in order to manage schema migrations of a BigQuery dataset at GreenSync. At the time of writing, we couldn't find any good tools in any language to manage changes to the schema as a set of migrations.

Beyond migrations, I'm unsure how useful this gem is. I haven't yet tested what the performance would be for data interactions vs. directly using the `google-cloud-bigquery` gem's native facilities. If you're inserting a bunch of data, it's probably a better idea to use an [inserter from that gem](https://googleapis.dev/ruby/google-cloud-bigquery/latest/Google/Cloud/Bigquery/Dataset.html#insert_async-instance_method) rather than going through SQL.

## Contents

<!-- MarkdownTOC autolink=true -->

- [Intro](#intro)
- [Quirks](#quirks)
  - [Creating tables with column defaults](#creating-tables-with-column-defaults)
  - [Transactions](#transactions)
  - [Update statements without `WHERE`](#update-statements-without-where)
  - [Combining statements](#combining-statements)
  - [Alter table](#alter-table)
  - [Column recreation](#column-recreation)
- [Installation](#installation)
- [Usage](#usage)
- [Contributing](#contributing)
- [Development](#development)
  - [Pre-push hook](#pre-push-hook)
  - [Release](#release)

<!-- /MarkdownTOC -->

## Intro

**Be warned: Given I was unable to find Sequel documentation covering how to write a database adapter, this was put together by reading Sequel's source and hacking at things until they worked. There are probably a lot of rough edges.**

Features:

- Connecting
- Migrating (see quirks)
- Table creation (see quirks)
- Inserting rows
- Updating rows (see quirks)
- Querying
- Transactions (see quirks)
- Table partitioning
- Ruby types:
  + String
  + Integer
  + _Boolean_ (`TrueClass`/`FalseClass`)
  + DateTime (note that BigQuery does not persist timezone)
  + Date
  + Float
  + BigDecimal
- Selecting the BigQuery server location

## Quirks

### Creating tables with column defaults

BigQuery doesn't support defaults on columns. As a workaround, all defaults are automatically removed from statements (crudely).

### Transactions

BigQuery doesn't support transactions where the statements are executed individually. It does support them if entire transaction SQL is sent all at once though. As a workaround, buffering of statements within a transaction has been implemented. However, the impact of this is that no results can be returned within a transaction.

### Update statements without `WHERE`

BigQuery requires all `UPDATE` statement to have a `WHERE` clause. As a workaround, statements which lack one have `where 1 = 1` appended automatically (crudely).

### Combining statements

When combining multiple statements into one query (with `;`), and the final statement is not a `SELECT`, the `google-cloud-bigquery` gem has a [bug](https://github.com/googleapis/google-cloud-ruby/issues/9617) which causes an exception. Note that all the statements have been executed when this happens. A workaround is to append `; SELECT 1`.

### Alter table

BigQuery [rate-limits alter table statements](https://cloud.google.com/bigquery/quotas#dataset_limits) to 10 per second. This is mitigated somewhat by Sequel combining `ALTER TABLE` statements whenever possible, and BigQuery having extremely high latency (\~2 seconds per query); but you may still run into this limitation.

We've also noticed a bug with `google-cloud-bigquery` where an `ALTER TABLE` statement resulted in a `NoMethodError` on nil for `fields` within `from_gapi_json`. We're not yet sure what caused this.

### Column recreation

Be careful when deleting a column which you might want to re-add. BigQuery reserves the name of a deleted column for up to the time travel duration - which is [*seven days*](https://cloud.google.com/bigquery/docs/time-travel). Re-creating the entire dataset is a painful workaround.

## Installation

Add it to the `Gemfile` of your project:

```ruby
gem 'sequel-bigquery'
```

and install all your gems:

```bash
bundle install
```

Or you can install it to your system directly using:

```bash
gem install sequel-bigquery
```

## Usage

Connect to BigQuery:

```
require 'sequel-bigquery'
require 'logger'

db = Sequel.connect(
  adapter: :bigquery,
  project: 'your-gcp-project',
  database: 'your_bigquery_dataset_name',
  location: 'australia-southeast2',
  logger: Logger.new(STDOUT),
)
```

And use Sequel like normal.

Note that it is important to supply a logger that will at least output warning messages so you know when your queries are being modifed or buffered, which may be unexpected behaviour.

## Contributing

Pull requests welcome! =)

## Development

### Pre-push hook

This hook runs style checks and tests.

To set up the pre-push hook:

```bash
echo -e "#\!/bin/bash\n\$(dirname \$0)/../../auto/pre-push-hook" > .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

### Release

To release a new version:

```bash
auto/release/update-version && auto/release/tag && auto/release/publish
```

This takes care of the whole process:

- Incrementing the version number (the patch number by default)
- Tagging & pushing commits
- Publishing the gem to RubyGems
- Creating a draft GitHub release

To increment the minor or major versions instead of the patch number, run `auto/release/update-version` with `--minor` or `--major`.
