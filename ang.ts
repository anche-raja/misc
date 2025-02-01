function normalizeBase(base: string): string {
  // Ensure it starts with a slash and ends with a slash
  if (!base.startsWith('/')) {
    base = '/' + base;
  }
  if (!base.endsWith('/')) {
    base = base + '/';
  }
  return base;
}


const baseEl = document.querySelector('base');
if (baseEl) {
  const normalizedBase = normalizeBase(config.environment.webBase);
  baseEl.setAttribute('href', normalizedBase);
  console.log('Base href set to:', normalizedBase);
} else {
  // Fallback: Create a base element if it doesn't exist (ideally this branch never executes)
  const newBaseEl = document.createElement('base');
  const normalizedBase = normalizeBase(config.environment.webBase);
  newBaseEl.setAttribute('href', normalizedBase);
  document.head.insertBefore(newBaseEl, document.head.firstChild);
  console.log('Base element created with href:', normalizedBase);
}
