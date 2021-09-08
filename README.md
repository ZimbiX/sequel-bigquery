# sequel-bigquery

[![CI status](https://github.com/ZimbiX/sequel-bigquery/actions/workflows/main.yml/badge.svg?branch=master)](https://github.com/ZimbiX/sequel-bigquery/actions/workflows/main.yml) [![Gem Version](https://badge.fury.io/rb/sequel-bigquery.svg)](https://rubygems.org/gems/sequel-bigquery)

A Sequel adapter for [Google's BigQuery](https://cloud.google.com/bigquery).

## Contents

<!-- MarkdownTOC autolink=true -->

- [Intro](#intro)
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
- Migrating
- Table creation, with automatic removal of defaults from statements (since BigQuery doesn't support it)
- Inserting rows
- Updating rows, with automatic addition of `where 1 = 1` to statements (since BigQuery requires a `where` clause)
- Querying
- Transactions (buffered since BigQuery only supports them when you execute the whole transaction at once)
- Ruby types:
  + String
  + Integer
  + _Boolean_ (`TrueClass`/`FalseClass`)
  + DateTime (note that BigQuery does not persist timezone)
  + Date
  + BigDecimal

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

db = Sequel.connect(
  adapter: :bigquery,
  project: 'your-gcp-project',
  database: 'your_bigquery_dataset_name',
  logger: Logger.new(STDOUT),
)
```

And use Sequel like normal.

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
