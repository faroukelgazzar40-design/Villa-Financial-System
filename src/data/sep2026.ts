import type { IncomeTxn } from '../types'

export const sep2026Data: IncomeTxn[] = [
  // September daily transactions (8/1 offices already in aug2026.ts)
  // VAT entries
  { id: 'sep26-001', date: '2026-09-01', amount: 2800, salesPerson: 'Villa', category: 'Other', space: 'VAT', paymentMethod: 'Bank Transfer', paymentStatus: 'Done', branch: '6 October', comment: 'VAT' },
  { id: 'sep26-002', date: '2026-09-01', amount: 700, salesPerson: 'Villa', category: 'Other', space: 'VAT', paymentMethod: 'Bank Transfer', paymentStatus: 'Done', branch: 'Nasr City', comment: 'VAT' },
  // September daily transactions
  { id: 'sep26-003', date: '2026-09-02', amount: 2880, salesPerson: 'Yasmen', category: 'Virtual Office', space: 'Virtual', paymentMethod: 'Instapay', paymentStatus: 'Done', branch: '6 October', comment: 'V Renewal' },
  { id: 'sep26-004', date: '2026-09-03', amount: 3000, salesPerson: 'Shahd', category: 'Meeting Room', space: 'Meeting', paymentMethod: 'Cash', paymentStatus: 'Done', branch: 'Nasr City', comment: '' },
  { id: 'sep26-005', date: '2026-09-04', amount: 1500, salesPerson: 'Mariam', category: 'Other', space: 'hours', paymentMethod: 'Cash', paymentStatus: 'Done', branch: '6 October', comment: 'hours' },
  { id: 'sep26-006', date: '2026-09-05', amount: 4000, salesPerson: 'Yasmen', category: 'Virtual Office', space: 'Virtual', paymentMethod: 'Bank Transfer', paymentStatus: 'Done', branch: 'Nasr City', comment: '' },
  // West Gate branch entries
  { id: 'sep26-007', date: '2026-09-01', amount: 9000, salesPerson: 'Villa', category: 'Office Space', space: 'WG-01', paymentMethod: 'Bank Transfer', paymentStatus: 'Done', branch: 'West Gate', comment: 'west gate' },
  { id: 'sep26-008', date: '2026-09-01', amount: 9000, salesPerson: 'Villa', category: 'Office Space', space: 'WG-02', paymentMethod: 'Bank Transfer', paymentStatus: 'Done', branch: 'West Gate', comment: 'west gate' },
]
