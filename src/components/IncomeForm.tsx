import { useState } from 'react'
import { X } from 'lucide-react'
import { useStore } from '../store'
import { IncomeTxn, BRANCHES, INCOME_CATEGORIES, PAYMENT_METHODS, SALES_PEOPLE } from '../types'
import { format } from 'date-fns'

interface Props {
  existing?: IncomeTxn
  onClose: () => void
}

const emptyForm = (): Omit<IncomeTxn, 'id'> => ({
  date: format(new Date(), 'yyyy-MM-dd'),
  amount: 0,
  salesPerson: 'Villa',
  category: 'Office Space',
  space: '',
  paymentMethod: 'Cash',
  paymentStatus: 'Done',
  branch: '6 October',
  comment: '',
})

export function IncomeForm({ existing, onClose }: Props) {
  const { addIncome, updateIncome } = useStore()
  const [form, setForm] = useState<Omit<IncomeTxn, 'id'>>(
    existing ? { ...existing } : emptyForm()
  )

  function set(field: string, value: string | number) {
    setForm((f) => ({ ...f, [field]: value }))
  }

  function submit(e: React.FormEvent) {
    e.preventDefault()
    if (existing) {
      updateIncome(existing.id, form)
    } else {
      addIncome(form)
    }
    onClose()
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl w-full max-w-lg shadow-xl">
        <div className="flex items-center justify-between p-5 border-b">
          <h2 className="font-semibold text-slate-800">{existing ? 'Edit' : 'Add'} Income Transaction</h2>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-600"><X size={20} /></button>
        </div>
        <form onSubmit={submit} className="p-5 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <label className="block">
              <span className="text-xs font-medium text-slate-500 mb-1 block">Date *</span>
              <input type="date" required value={form.date} onChange={(e) => set('date', e.target.value)}
                className="w-full border border-slate-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            </label>
            <label className="block">
              <span className="text-xs font-medium text-slate-500 mb-1 block">Amount (EGP) *</span>
              <input type="number" required min="0" value={form.amount || ''} onChange={(e) => set('amount', parseFloat(e.target.value) || 0)}
                className="w-full border border-slate-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            </label>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <label className="block">
              <span className="text-xs font-medium text-slate-500 mb-1 block">Branch *</span>
              <select value={form.branch} onChange={(e) => set('branch', e.target.value)}
                className="w-full border border-slate-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500">
                {BRANCHES.map((b) => <option key={b}>{b}</option>)}
              </select>
            </label>
            <label className="block">
              <span className="text-xs font-medium text-slate-500 mb-1 block">Category *</span>
              <select value={form.category} onChange={(e) => set('category', e.target.value)}
                className="w-full border border-slate-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500">
                {INCOME_CATEGORIES.map((c) => <option key={c}>{c}</option>)}
              </select>
            </label>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <label className="block">
              <span className="text-xs font-medium text-slate-500 mb-1 block">Sales Person *</span>
              <select value={form.salesPerson} onChange={(e) => set('salesPerson', e.target.value)}
                className="w-full border border-slate-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500">
                {SALES_PEOPLE.map((s) => <option key={s}>{s}</option>)}
              </select>
            </label>
            <label className="block">
              <span className="text-xs font-medium text-slate-500 mb-1 block">Space / Office</span>
              <input type="text" value={form.space} onChange={(e) => set('space', e.target.value)} placeholder="e.g. Office #1, NC-03"
                className="w-full border border-slate-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            </label>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <label className="block">
              <span className="text-xs font-medium text-slate-500 mb-1 block">Payment Method *</span>
              <select value={form.paymentMethod} onChange={(e) => set('paymentMethod', e.target.value)}
                className="w-full border border-slate-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500">
                {PAYMENT_METHODS.map((m) => <option key={m}>{m}</option>)}
              </select>
            </label>
            <label className="block">
              <span className="text-xs font-medium text-slate-500 mb-1 block">Payment Status *</span>
              <select value={form.paymentStatus} onChange={(e) => set('paymentStatus', e.target.value)}
                className="w-full border border-slate-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500">
                <option>Done</option>
                <option>Pending</option>
                <option>Partial</option>
              </select>
            </label>
          </div>

          <label className="block">
            <span className="text-xs font-medium text-slate-500 mb-1 block">Comment</span>
            <input type="text" value={form.comment} onChange={(e) => set('comment', e.target.value)}
              className="w-full border border-slate-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
          </label>

          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose}
              className="flex-1 border border-slate-200 rounded-xl py-2.5 text-sm font-medium text-slate-600 hover:bg-slate-50">
              Cancel
            </button>
            <button type="submit"
              className="flex-1 bg-blue-600 text-white rounded-xl py-2.5 text-sm font-medium hover:bg-blue-700">
              {existing ? 'Update' : 'Add Transaction'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
