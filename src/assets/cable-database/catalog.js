const root = document.querySelector('[data-catalog]');
if (root) {
  const list = root.querySelector('#catalog-results');
  const records = [...list.children];
  const search = root.querySelector('#catalog-search');
  const speed = root.querySelector('#catalog-speed');
  const power = root.querySelector('#catalog-power');
  const sort = root.querySelector('#catalog-sort');
  const count = root.querySelector('#catalog-count');
  const clear = root.querySelector('#catalog-clear');
  function update() {
    const terms = search.value.trim().toLowerCase().split(/\s+/).filter(Boolean);
    let matches = 0;
    for (const row of records) {
      row.hidden = !terms.every(term => row.dataset.search.includes(term))
        || (speed.value && row.dataset.speed !== speed.value)
        || (power.value && row.dataset.power !== power.value);
      if (!row.hidden) matches++;
    }
    const ordered = [...records].sort((a,b) => {
      if (sort.value === 'speed') return Number(b.dataset.speedNumber)-Number(a.dataset.speedNumber) || a.dataset.name.localeCompare(b.dataset.name);
      if (sort.value === 'power') return Number(b.dataset.powerNumber)-Number(a.dataset.powerNumber) || a.dataset.name.localeCompare(b.dataset.name);
      return a.dataset.name.localeCompare(b.dataset.name);
    });
    for (const row of ordered) list.append(row);
    count.textContent = `${matches} of ${records.length} entries`;
    root.querySelector('#catalog-empty').hidden = matches !== 0;
    clear.disabled = !search.value && !speed.value && !power.value && sort.value === 'name';
  }
  [search, speed, power, sort].forEach(control => control.addEventListener(control === search ? 'input' : 'change', update));
  function reset() {
    search.value = speed.value = power.value = ''; sort.value = 'name'; update(); search.focus();
  }
  clear.addEventListener('click', reset);
  root.querySelector('#catalog-empty-reset').addEventListener('click', reset);
  root.querySelector('#catalog-controls').hidden = false;
  update();
}
