#!/usr/bin/env ruby
require_relative 'lib/helper'

class Foo < Struct.new(:a, :b)
  include Enumerable
  extend Forwardable
  def_delegators :@items, :size, :<<
  private_constant :SECRET
  SECRET = 1

  def each(&blk) = @items.each(&blk)
  def method_missing(name, *args, **kw, &blk)
    name.to_s.start_with?('get_') ? send(name.to_s.sub('get_', '')) : super
  end
  def respond_to_missing?(n, p = false) = true
  protected def helper; end
  class << self
    attr_accessor :config
    def build(*) = new(*)
  end
end

x = if true then 1 else 2 end
y = [1, 2, 3].map do |n| n ** 2 end.select(&:even?)
h = { "a" => 1, b: 2, "c": 3, **other }
s = 'single #{no} \' \n' + "double #{x} \"q\" \t é" + %q(parens (nested)) + %Q[#{x}] + `echo hi`
sym = %i[a b] + [:"quoted sym", :+, :[]]
r = %r{^/path/(\d+)$}ix
case x when 1..3 then puts "low" when Integer, Float then puts "num" else puts "other" end
puts <<-A + <<~B
  first #{x}
  A
  second
B
while (line = gets) && !line.empty?; puts line.chomp; end
begin; Integer('x'); rescue ArgumentError, TypeError => e; retry if false; ensure; end
lam = ->(a, b = 2) { a + b }
puts lam.(1), lam[1, 2], __method__.inspect, $stdout.sync, ENV['HOME'], $0
a, (b, *c), d = 1, [2, 3, 4], 5
x = y rescue z
alias_method :old, :new
BEGIN { puts 'start' }
__END__
data after end
