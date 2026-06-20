import { useState } from 'react'
import { X } from 'lucide-react'
import { useStore } from '../store'
import { ExpenseTxn, BRANCHES, EXPENSE_CATEGORIES, PAYMENT_METHODS } from '../types'
import { format } from 'date-fns'

interface Props {
  existing?: ExpenseTxn
  onClose: () => void
}

const emptyForm = (): Omit<ExpenseTxn, 'id'> => ({
  date: format(new Date(), 'yyyy-MM-dd'),
  amount: 0,
  category: 'Rent',
  description: '',
  paymentMethod: 'Cash',
  branch: '6 October',
  isRecurring: false,
  comment: '',
})

export function ExpenseForm({ existing, onClose }: Props) {
  const { addExpense, updateExpense } = useStore()
  const [form, setForm] = useState<Omit<ExpenseTxn, 'id'>>(
    existing ? { ...existing } : emptyForm()
  )

  function set(field: string, value: string | number | boolean) {
    setForm((f) => ({ ...f, [field]: value }))
  }

  function submit(e: React.FormEvent) {
    e.preventDefault()
    if (existing) {
      updateExpense(existing.id, form)
    } else {
      addExpense(form)
    }
    onClose()
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl w-full max-w-lg shadow-xl">
        <div className="flex items-center justify-between p-5 border-b">
          <h2 className="font-semibold text-slate-800">{existing ? 'Edit' : 'Add'} Expense</h2>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-600"><X size={20} /></button>
        </div>
        <form onSubmit={submit} className="p-5 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <label className="block">
              <span className="text-xs font-medium text-slate-500 mb-1 block">Date *</span>
              <input type="date" required value={form.date} onChange={(e) => set('date', e.target.value)}
                className="w-full border border-slate-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-red-400" />
            </label>
            <label className="block">
              <span className="text-xs font-medium text-slate-500 mb-1 block">Amount (EGP) *</span>
              <input type="number" required min="0" value={form.amount || ''} onChange={(e) => set('amount', parseFloat(e.target.value) || 0)}
                className="w-full border border-slate-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-red-400" />
            </label>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <label className="block">
              <span className="text-xs font-medium text-slate-500 mb-1 block">Category *</span>
              <select value={form.category} onChange={(e) => set('category', e.target.value)}
                className="w-full border border-slate-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-red-400">
                {EXPENSE_CATEGORIES.map((c) => <option key={c}>{c}</option>)}
              </select>
            </label>
            <label className="block">
              <span className="text-xs font-medium text-slate-500 mb-1 block">Branch *</span>
              <select value={form.branch} onChange={(e) => set('branch', e.target.value)}
                className="w-full border border-slate-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-red-400">
                {BRANCHES.map((b) => <option key={b}>{b}</option>)}
              </select>
            </label>
          </div>

          <label className="block">
            <span className="text-xs font-medium text-slate-500 mb-1 block">Description</span>
            <input type="text" value={form.description} onChange={(e) => set('description', e.target.value)}
              className="w-full border border-slate-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-red-400" />
          </label>

          <div className="grid grid-cols-2 gap-4">
            <label className="block">
              <span className="text-xs font-medium text-slate-500 mb-1 block">Payment Method *</span>
              <select value={form.paymentMethod} onChange={(e) => set('paymentMethod', e.target.value)}
                className="w-full border border-slate-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-red-400">
                {PAYMENT_METHODS.map((m) => <option key={m}>{m}</option>)}
              </select>
            </label>
            <label className="block">
              <span className="text-xs font-medium text-slate-500 mb-1 block">Recurring?</span>
              <div className="flex items-center gap-2 h-[38px]">
                <input type="checkbox" id="recurring" checked={form.isRecurring} onChange={(e) => set('isRecurring', e.target.checked)}
                  className="w-4 h-4 rounded" />
                <label htmlFor="recurring" className="text-sm text-slate-600">Fixed monthly</label>
              </div>
            </label>
          </div>

          <label className="block">
            <span className="text-xs font-medium text-slate-500 mb-1 block">Comment</span>
            <input type="text" value={form.comment} onChange={(e) => set('comment', e.target.value)}
              className="w-full border border-slate-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-red-400" />
          </label>

          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose}
              className="flex-1 border border-slate-200 rounded-xl py-2.5 text-sm font-medium text-slate-600 hover:bg-slate-50">
              Cancel
            </button>
            <button type="submit"
              className="flex-1 bg-red-500 text-white rounded-xl py-2.5 text-sm font-medium hover:bg-red-600">
              {existing ? 'Update' : 'Add Expense'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
