/* No external dependencies. Frozen cases and A/B mappings live on the local server. */
const app = document.querySelector('#app');
let session, index = 0, draft, saving = false;
const labels = {A:'A', B:'B', tie:'Equally good', neither:'Neither works', unsure:'Need more context'};
const names = {baseline:'Current instruction', candidate:'Revised instruction', tie:'Equally good', neither:'Neither works', unsure:'Need more context'};
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const draftKey = id => `shelf-eval:${session.run_id}:${session.dataset_sha256}:${id}`;

async function request(path, body) {
  let response;
  try {
    response = await fetch(path, body === undefined ? {} : {
      method:'POST', headers:{'Content-Type':'application/json','X-Review-Token':session.token}, body:JSON.stringify(body)
    });
  } catch {
    throw new Error('The local review server is unavailable. Your browser draft is kept. Restart the server, then reload this page to continue.');
  }
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || 'Request failed. Please try again.');
  return data;
}
function status(message, error=false) {
  const el = document.querySelector('#save-status');
  if (el) { el.textContent = message; el.classList.toggle('error',error); }
}
function stash() {
  if (session.revealed_at) return;
  try { localStorage.setItem(draftKey(draft.case_id), JSON.stringify(draft)); }
  catch { status('Browser draft unavailable. Use Save & next to save on this Mac.',true); }
}
function loadDraft(c) {
  let cached;
  try { cached = JSON.parse(localStorage.getItem(draftKey(c.id))); } catch { /* server state is authoritative fallback */ }
  return cached?.case_id === c.id ? cached : {...(session.judgments[c.id] || {case_id:c.id,choice:null,criteria:[],note:'',confidence:'unsure'})};
}
function book(b, label) {
  return `<section class="book" aria-label="${esc(label)}"><div class="eyebrow">${esc(label)}</div><h2>${esc(b.title)}</h2><p class="byline">${esc(b.author)}</p><p class="book-notes">${esc(b.notes)}</p><a class="source" href="${esc(b.source_url)}" target="_blank" rel="noopener noreferrer">Book source ↗</a></section>`;
}
function renderCase(target) {
  index = target;
  const c = session.cases[index];
  draft = loadDraft(c);
  app.innerHTML = `<div class="intro"><div><p class="eyebrow">${esc(session.run_id.replaceAll("-", " "))} · ${index+1} of ${session.cases.length}</p><h1>Which explanation helps you choose?</h1><p class="sub">Read as this reader. Compare the connection—not whether you personally like the book.</p></div><button class="text-button" id="view-results">Review choices</button></div>
  <nav class="progress" aria-label="Review cases">${session.cases.map((item,i)=>`<button class="step ${session.judgments[item.id]?'done':''} ${index===i?'current':''}" data-go="${i}" aria-label="Case ${i+1}${session.judgments[item.id]?', saved':''}" ${index===i?'aria-current="step"':''}></button>`).join('')}</nav>
  <section class="context"><p class="eyebrow">The reader · fictional profile</p><p class="reader">${esc(c.reader)}</p><div class="books">${book(c.seed,'Loved')}${book(c.recommendation,'Considering')}</div></section>
  <p class="prompt" id="choice-label">Which would you show this reader?</p>
  <div class="options" role="group" aria-labelledby="choice-label">${['A','B'].map(side=>`<button class="option ${draft.choice===side?'selected':''}" data-choice="${side}" aria-pressed="${draft.choice===side}" aria-label="Choose explanation ${side}"><span class="option-top"><span class="option-letter">EXPLANATION ${side}</span><span class="radio-dot" aria-hidden="true"></span></span>${c.options[side]?`<span class="because">Because you loved ${esc(c.seed.title)}</span><span class="reason">${esc(c.options[side])}</span>`:`<span class="abstention">No explanation shown.<br>This version chose not to claim a connection.</span>`}</button>`).join('')}</div>
  <div class="other-choices">${['tie','neither','unsure'].map(v=>`<button class="choice ${draft.choice===v?'selected':''}" data-choice="${v}" aria-pressed="${draft.choice===v}">${labels[v]}</button>`).join('')}</div>
  <p class="criteria-guide"><span class="guide-label">Accurate:</span> supported by both books. <span class="guide-label">Specific:</span> more than a shared genre. <span class="guide-label">Useful:</span> relevant to this reader.</p>
  <section class="why"><p class="why-title">What mattered? <span class="optional">Optional, but helpful for teaching the evaluator.</span></p>
  <div class="criteria">${[['accuracy','Accuracy'],['specificity','Specificity'],['usefulness','Usefulness']].map(([value,label])=>`<label><input type="checkbox" name="criterion" value="${value}" ${draft.criteria.includes(value)?'checked':''}>${label}</label>`).join('')}</div>
  <textarea id="note" aria-label="Why did you choose this?" maxlength="2000" placeholder="A short reason—for example, what felt honest, vague, or misleading.">${esc(draft.note)}</textarea>
  <fieldset class="confidence"><legend class="sr-only">Confidence in your judgment</legend><span>How sure are you?</span>${[['confident','Confident'],['unsure','Not sure']].map(([value,label])=>`<label><input type="radio" name="confidence" value="${value}" ${draft.confidence===value?'checked':''}>${label}</label>`).join('')}</fieldset></section>
  <div class="actions"><button class="secondary" id="previous" ${index===0?'disabled':''}>Previous</button><button class="primary" id="save" ${!draft.choice?'disabled':''}>${index===session.cases.length-1?'Save & finish':'Save & next'} →</button></div>
  <p class="save-status" id="save-status" role="status">${session.judgments[c.id]?'Saved. You can change your choice before revealing versions.':'Your notes stay private on this Mac.'}</p>
  <p class="footer-note">A and B change places between cases. “Equally good” means both work; “Neither works” means both fail. If the notes are insufficient, choose “Need more context.” ${session.split === "development" ? "Five separate cases are reserved for the final check." : "These are the reserved final-check cases."}</p>`;
  document.querySelectorAll('[data-choice]').forEach(button=>button.addEventListener('click',()=>{
    draft.choice = button.dataset.choice;
    document.querySelectorAll('[data-choice]').forEach(b=>{const chosen=b.dataset.choice===draft.choice;b.classList.toggle('selected',chosen);b.setAttribute('aria-pressed',String(chosen));});
    document.querySelector('#save').disabled = false; stash(); status('Draft saved in this browser. Save & next writes your judgment to disk.');
  }));
  document.querySelector('#note').addEventListener('input',e=>{draft.note=e.target.value;stash();});
  document.querySelectorAll('[name="criterion"]').forEach(input=>input.addEventListener('change',()=>{draft.criteria=[...document.querySelectorAll('[name="criterion"]:checked')].map(i=>i.value);stash();}));
  document.querySelectorAll('[name="confidence"]').forEach(input=>input.addEventListener('change',()=>{draft.confidence=input.value;stash();}));
  document.querySelector('#save').addEventListener('click',saveAndNext);
  document.querySelector('#previous').addEventListener('click',()=>{stash();renderCase(index-1);});
  document.querySelectorAll('[data-go]').forEach(b=>b.addEventListener('click',()=>{stash();renderCase(Number(b.dataset.go));}));
  document.querySelector('#view-results').addEventListener('click',()=>{stash();showResults();});
  window.scrollTo({top:0,behavior:'instant'});
}
async function saveAndNext() {
  if (saving || !draft.choice) return;
  saving = true; const button = document.querySelector('#save'); button.disabled=true; button.textContent='Saving…';
  try {
    const saved = await request('/api/judgment',draft); session.judgments[saved.case_id]=saved;
    try { localStorage.removeItem(draftKey(saved.case_id)); } catch { /* saved on disk */ }
    if (index < session.cases.length-1) renderCase(index+1); else await showResults();
  } catch (error) { status(error.message,true); button.disabled=false;button.textContent='Retry save →'; }
  finally { saving=false; }
}
async function showResults() {
  try {
    const result = await request('/api/results'); const count = Object.keys(session.judgments).length;
    const revealed = Boolean(result.revealed_at); session.revealed_at=result.revealed_at;
    app.innerHTML = `<div class="summary-header"><p class="eyebrow">${esc(session.run_id.replaceAll("-", " "))} · ${count} of ${session.cases.length} saved</p><h1>${result.complete?'Your first eval is in.':'Your choices so far.'}</h1><p class="sub">${revealed?'These are observations from a small practice set, not proof that one prompt is better. Your reasons and disagreements are the useful part.':result.complete?'Review your choices before revealing the versions. Revealing locks this round so later knowledge cannot change your blind judgments.':'You can pause here and come back. Choices saved with “Save & next” are stored on this Mac.'}</p></div>
    ${result.totals?`<div class="tally">${Object.entries(result.totals).map(([k,v])=>`<div class="tally-item"><strong>${v}</strong>${names[k]}</div>`).join('')}</div>`:''}
    <div class="exports">${!revealed?(result.complete?'<button class="primary" id="reveal">Reveal versions & lock judgments</button>':'<button class="primary" id="continue">Continue review →</button>'):''}<a href="/api/export.csv" download>Download results CSV</a><a href="/api/export.json" download>Download full review</a></div>
    <div class="table-wrap"><table><thead><tr><th>Book comparison</th><th>Your choice</th><th>Your reason</th>${revealed?'<th>Version</th>':'<th></th>'}</tr></thead><tbody>${result.rows.map((row,i)=>`<tr><td><div class="table-book">${esc(row.recommendation)}</div><div class="table-seed">From ${esc(row.seed)}</div></td><td>${row.judgment?labels[row.judgment.choice]:'Not saved'}</td><td>${esc(row.judgment?.note || '—')}${row.judgment?.criteria.length?`<div class="table-seed">${row.judgment.criteria.map(esc).join(' · ')}</div>`:''}</td><td>${revealed?esc(names[row.preferred_variant]):`<button class="text-button" data-review="${i}">${row.judgment?'Review':'Judge'}</button>`}</td></tr>`).join('')}</tbody></table></div>
    ${revealed?`<details><summary>What changed between the prompts?</summary><p class="sub">Both versions used the same model, book notes, fictional reader and short display limits. The baseline is Shelf’s current explanation-field instruction in an isolated test, not a replay of the full recommendation pipeline.</p><h3 class="prompt">Current instruction</h3><div class="changed-prompt">${esc(result.prompts.baseline)}</div><h3 class="prompt">Added instruction</h3><div class="changed-prompt">${esc(result.prompts.candidate.replace(result.prompts.baseline.trim(), '').trim())}</div></details><p class="footer-note">Next: review the cases where your choice was close or neither worked. Use those reasons to refine a judging rubric, then compare an AI judge with your saved decisions. ${session.split === "development" ? "The five held-out cases remain untouched." : "These final-check cases have now been used; reserve new cases for the next experiment."}</p>`:'<p class="footer-note">Version identities and scores stay hidden until every case has a saved choice. “Need more context” is recorded separately from a tie or a rejection.</p>'}
    <p class="save-status" id="save-status" role="status"></p>`;
    document.querySelectorAll('[data-review]').forEach(b=>b.addEventListener('click',()=>renderCase(Number(b.dataset.review))));
    document.querySelector('#continue')?.addEventListener('click',()=>renderCase(session.cases.findIndex(c=>!session.judgments[c.id])));
    document.querySelector('#reveal')?.addEventListener('click',async()=>{const b=document.querySelector('#reveal');b.disabled=true;try{await request('/api/reveal',{});await showResults();}catch(e){status(e.message,true);b.disabled=false;}});
    window.scrollTo({top:0,behavior:'instant'});
  } catch (error) { status(error.message,true); }
}
async function boot() {
  try {
    session = await request('/api/session'); app.setAttribute('aria-busy','false');
    if (session.revealed_at || session.complete) await showResults();
    else renderCase(Math.max(0,session.cases.findIndex(c=>!session.judgments[c.id])));
  } catch (error) {
    app.setAttribute('aria-busy','false');
    app.innerHTML=`<section class="fatal"><h1>Couldn’t open the review.</h1><p class="sub">${esc(error.message)} Your saved judgments are still on disk.</p><button class="primary" id="retry">Try again</button></section>`;
    document.querySelector('#retry').addEventListener('click',boot);
  }
}
boot();
