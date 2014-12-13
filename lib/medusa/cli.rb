module Medusa
  module CLI
    COMMANDS = %w[count cron pagedepth serialize url-list]

    def self.run
      command = ARGV.shift

      if COMMANDS.include? command
        load "medusa/cli/#{command.tr('-', '_')}.rb"
      else
        puts <<-INFO
Medusa is a web spider framework that can collect
useful information about pages it visits.

Usage:
  medusa <command> [arguments]

Commands:
  #{COMMANDS.join(', ')}
INFO
      end
    end
  end
end
