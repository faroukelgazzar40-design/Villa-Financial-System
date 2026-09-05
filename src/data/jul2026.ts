import type { IncomeTxn } from '../types'

export const jul2026Data: IncomeTxn[] = [
  // July 2026 – sparse data (VAT entries only from raw sheet)
  { id: 'jul26-001', date: '2026-07-06', amount: 700, salesPerson: 'Villa', category: 'Other', space: 'VAT', paymentMethod: 'Bank Transfer', paymentStatus: 'Done', branch: 'Nasr City', comment: 'VAT' },
  { id: 'jul26-002', date: '2026-07-08', amount: 1260, salesPerson: 'Villa', category: 'Other', space: 'VAT', paymentMethod: 'Bank Transfer', paymentStatus: 'Done', branch: '6 October', comment: 'VAT' },
]
