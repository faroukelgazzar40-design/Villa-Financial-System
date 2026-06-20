export function formatEGP(amount: number): string {
  return new Intl.NumberFormat('en-EG', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(amount) + ' EGP'
}

export function formatNumber(amount: number): string {
  return new Intl.NumberFormat('en-EG').format(amount)
}
