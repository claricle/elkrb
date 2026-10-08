# frozen_string_literal: true

# Every spelling of a padding or a vector with one bad component, so a spec
# can prove each component of each spelling is validated.
module StructuredOptionForms
  SIDES = %i[top left bottom right].freeze
  AXES = %i[x y].freeze
  # Each reads as 0.0, or as absent, through String#to_f or `||`.
  BAD_COMPONENTS = ["abc", "0x10", "1e", "", false].freeze

  # @return [Hash{String => Object}] spelling name => padding value with
  #   `bad` as `side` and 1 elsewhere
  def self.paddings(side, bad)
    others = SIDES - [side]
    {
      "string" => "[#{[[side, bad], *others.map { |o| [o, 1] }]
        .map { |k, v| "#{k}=#{v}" }.join(',')}]",
      "String-keyed hash" => { side.to_s => bad },
      "Symbol-keyed hash" => { side => bad },
    }
  end

  # @return [Hash{String => Object}] spelling name => vector value with
  #   `bad` as `axis` and 1 as the other
  def self.vectors(axis, bad)
    pair = axis == :x ? [bad, 1] : [1, bad]
    {
      "string" => "(#{pair.join(',')})",
      "Symbol-keyed hash" => AXES.zip(pair).to_h,
      "String-keyed hash" => AXES.zip(pair).to_h { |k, v| [k.to_s, v] },
      "array" => pair,
    }
  end
end
