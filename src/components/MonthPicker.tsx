import { ChevronLeft, ChevronRight } from 'lucide-react'
import { format, addMonths, subMonths, parseISO } from 'date-fns'
import { useStore } from '../store'

export function MonthPicker() {
  const { selectedMonth, setSelectedMonth } = useStore()

  const current = parseISO(selectedMonth + '-01')

  return (
    <div className="flex items-center gap-2 bg-white border border-slate-200 rounded-xl px-3 py-2">
      <button
        onClick={() => setSelectedMonth(format(subMonths(current, 1), 'yyyy-MM'))}
        className="p-1 hover:bg-slate-100 rounded-lg transition-colors"
      >
        <ChevronLeft size={16} />
      </button>
      <span className="text-sm font-semibold text-slate-700 min-w-[110px] text-center">
        {format(current, 'MMMM yyyy')}
      </span>
      <button
        onClick={() => setSelectedMonth(format(addMonths(current, 1), 'yyyy-MM'))}
        className="p-1 hover:bg-slate-100 rounded-lg transition-colors"
      >
        <ChevronRight size={16} />
      </button>
    </div>
  )
}
