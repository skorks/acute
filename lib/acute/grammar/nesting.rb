module Acute
  # An item's atoms nested by size, the coarsest outside
  class Grammar
    private

    def pair(x, xs, y, ys)
      a = size(x)
      b = size(y)
      a >= b ? nest(x, y, a == b, ys) : nest(y, x, false, xs)
    end

    def combine(atoms, starts)
      return atoms[0] if atoms.size == 1
      return pair(atoms[0], starts[0], atoms[1], starts[1]) if atoms.size == 2
      sizes = atoms.map { size(_1) }
      # coarsest first, in the order said among equals; an insertion sort, as there are only a few
      order = []
      j = 0
      while j < sizes.size
        k = order.size
        k -= 1 while k > 0 && sizes[order[k - 1]] < sizes[j]
        order.insert(k, j)
        j += 1
      end
      node = atoms[order[0]]
      o = 1
      while o < order.size
        j = order[o]
        node = nest(node, atoms[j], sizes[j] == sizes[order[o - 1]], starts[j])
        return node if Failure === node
        o += 1
      end
      node
    end

    # a inside node, the coarser; same: the two are the same size, which conflicts but for a weekday and a date
    def nest(node, a, same, start)
      if same && !(Weekday === a && Date === node && node.day) && !(Date === a && a.day && Weekday === node)
        return failure(:conflict, start)
      end
      return failure(:conflict, start) if Unit === a || Unit === node
      # D37: a weekday with a date only picks among the date's readings
      Weekday === node && Date === a ? Within.new(node, a) : Within.new(a, node)
    end

    # "23 oct" + "2026", or "10/23" + "2026", is one date
    def merge_year(atoms, starts)
      y = atoms.index { |a| Date === a && a.year && a.month.nil? && a.sep.nil? }
      return unless y
      d = atoms.index { |a| Date === a && a.year.nil? && a.month }
      return unless d
      atoms[d] = Date.new(atoms[y].year, atoms[d].month, atoms[d].day, atoms[d].sep, atoms[y].short)
      atoms.delete_at(y)
      starts.delete_at(y)
    end

    # How coarse a constituent is, for nesting: clock 0, part 1, day 2, week 3, month 5, season 6, year 7
    def size(a)
      case KIND[a.class]
      when :clock, :approx then 0
      when :part then 1
      when :day_ref, :weekday, :holiday then 2
      when :weekend, :iso_week then 3
      when :date then a.day ? 2 : a.month ? 5 : 7
      when :season then 6
      when :fiscal then 7
      when :unit, :years then UNIT_SIZE[a.unit]
      when :rel then size(a.node)
      when :fuzzy then size(a.node) - 1
      when :nth then Unit === a.node ? UNIT_SIZE[a.node.unit] : size(a.node)
      when :shift then UNIT_SIZE[a.unit] >= 2 ? 2 : 0
      when :within then size(a.inner)
      when :range then size(a.from)
      else 2
      end
    end
  end
end
