# frozen_string_literal: true
require 'json'

module Demo
  VERSION = "1.0"

  class Account < Base
    include Comparable
    attr_reader :owner, :balance
    @@count = 0

    def initialize(owner, balance = 0)
      @owner = owner
      @balance = balance
      @@count += 1
    end

    def <=>(other)
      balance <=> other.balance
    end

    def to_s
      "#{owner}: #{'%.2f' % balance} \"quoted\"\n"
    end

    def self.build(**opts, &block)
      new(opts[:owner], opts.fetch(:balance, 0)).tap(&block)
    end
  end
end

items = %w[a b c].map { |x| x.upcase }
sym = :symbol
hash = { key: 1, "str" => [1, 2], other: nil }
re = /(\d+)-(?<word>\w+)/i
text = <<~HEREDOC
  heredoc with #{sym}
  second line
HEREDOC

items.each_with_index do |item, i|
  puts "#{i}: #{item}" if i.even? && !item.empty?
end

begin
  raise ArgumentError, 'bad'
rescue StandardError => e
  warn e.message
ensure
  puts 'done'
end
=begin
block comment
=end
