const MAX_PEOPLE = 5;

const cardRail = document.getElementById('cardRail');
const slotCount = document.getElementById('slotCount');
const overlay = document.getElementById('overlay');
const closeModalBtn = document.getElementById('closeModal');
const addForm = document.getElementById('addForm');
const formError = document.getElementById('formError');

let people = [];

async function loadPeople() {
  const res = await fetch('/api/people');
  people = await res.json();
  render();
}

function render() {
  cardRail.innerHTML = '';
  slotCount.textContent = `${people.length} / ${MAX_PEOPLE} cards filed`;

  for (let i = 0; i < MAX_PEOPLE; i++) {
    const slot = document.createElement('div');
    slot.className = 'card-slot';

    if (i < people.length) {
      slot.appendChild(buildCard(people[i]));
    } else {
      const empty = document.createElement('button');
      empty.className = 'slot-empty';
      empty.textContent = '+';
      empty.addEventListener('click', openModal);
      slot.appendChild(empty);
    }
    cardRail.appendChild(slot);
  }
}

function buildCard(person) {
  const flip = document.createElement('div');
  flip.className = 'flip-card';

  flip.innerHTML = `
    <div class="card-face card-front">
      <span class="tab">FILE #${String(person.id).padStart(3, '0')}</span>
      <div class="front-name">${escapeHtml(person.name)}</div>
      <div class="front-hint">tap to read &rarr;</div>
    </div>
    <div class="card-face card-back">
      <div>
        <div class="back-label">AGE</div>
        <div class="back-value">${escapeHtml(String(person.age))}</div>
        <div class="back-label">AREA</div>
        <div class="back-value">${escapeHtml(person.area)}</div>
      </div>
      <button class="remove-btn" data-id="${person.id}">Remove card</button>
    </div>
  `;

  flip.addEventListener('click', (e) => {
    if (e.target.classList.contains('remove-btn')) return;
    flip.classList.toggle('flipped');
  });

  flip.querySelector('.remove-btn').addEventListener('click', async (e) => {
    e.stopPropagation();
    const id = e.target.dataset.id;
    await fetch(`/api/people/${id}`, { method: 'DELETE' });
    await loadPeople();
  });

  return flip;
}

function escapeHtml(str) {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

function openModal() {
  formError.textContent = '';
  addForm.reset();
  overlay.classList.add('open');
}
function closeModal() {
  overlay.classList.remove('open');
}

closeModalBtn.addEventListener('click', closeModal);
overlay.addEventListener('click', (e) => {
  if (e.target === overlay) closeModal();
});

addForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  formError.textContent = '';

  const name = document.getElementById('fieldName').value.trim();
  const age = document.getElementById('fieldAge').value;
  const area = document.getElementById('fieldArea').value.trim();

  const submitBtn = addForm.querySelector('.stamp-btn');
  submitBtn.disabled = true;

  try {
    const res = await fetch('/api/people', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, age, area }),
    });
    const data = await res.json();

    if (!res.ok) {
      formError.textContent = data.error || 'something went wrong';
      submitBtn.disabled = false;
      return;
    }

    closeModal();
    await loadPeople();
  } catch (err) {
    formError.textContent = 'could not reach the server';
  } finally {
    submitBtn.disabled = false;
  }
});

loadPeople();
