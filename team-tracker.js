const teamTracker = (() => {
  let boards = [], lists = [], cards = [], members = [], selectedBoardId = null, loadedOrgId = null, currentPage = 'boards', loading = false, loadError = '';
  const trackerKey = () => `onward-board:${currentWorkspace?.organization_id || ''}`;
  const dateLabel = value => value ? new Date(`${value}T12:00:00`).toLocaleDateString(undefined, {month:'short',day:'numeric'}) : '';
  const memberName = id => members.find(m => m.user_id === id)?.email?.split('@')[0] || 'Unassigned';
  const update = async (query, success='Saved.') => {
    const {error} = await query;
    if(error) throw error;
    toast(success);
  };
  async function load() {
    if (!currentWorkspace || !db) return;
    loading = true; loadError = '';
    const org = currentWorkspace.organization_id;
    try {
      if(loadedOrgId!==org){boards=[];lists=[];cards=[];members=[];selectedBoardId=null;}
      const [boardResult, memberResult] = await Promise.all([
        db.from('team_boards').select('*').eq('organization_id', org).order('updated_at', {ascending:false}),
        db.rpc('list_workspace_members', {p_organization_id:org})
      ]);
      if(boardResult.error) throw boardResult.error;
      if(memberResult.error) throw memberResult.error;
      loadedOrgId=org;
      boards = boardResult.data || []; members = memberResult.data || [];
      selectedBoardId = boards.some(b => b.id === selectedBoardId) ? selectedBoardId : (boards.find(b=>b.id===(localStorage.getItem(trackerKey())||localStorage.getItem(trackerKey().replace('onward-','devlearn-'))))?.id || boards[0]?.id || null);
      if(selectedBoardId) {
        localStorage.setItem(trackerKey(), selectedBoardId);
        const [listResult, cardResult] = await Promise.all([
          db.from('team_board_lists').select('*').eq('organization_id',org).eq('board_id',selectedBoardId).order('position'),
          db.from('team_board_cards').select('*').eq('organization_id',org).eq('board_id',selectedBoardId).order('position')
        ]);
        if(listResult.error) throw listResult.error;
        if(cardResult.error) throw cardResult.error;
        lists = listResult.data || []; cards = cardResult.data || [];
      } else { lists=[]; cards=[]; }
    } catch(error) {
      loadError = /PGRST|does not exist|schema cache/i.test(error.message||'')
        ? 'The team tracker tables are not installed in Supabase yet. Apply the latest supabase/schema.sql migration, then reload.'
        : (error.message || 'Could not load this team board.');
    } finally { loading = false; }
  }
  function memberPicker(selected='') {
    return `<option value="">No assignee</option>${members.map(m=>`<option value="${esc(m.user_id)}" ${m.user_id===selected?'selected':''}>${esc(m.email||'Team member')} · ${esc(m.role)}</option>`).join('')}`;
  }
  function renderBoards() {
    const page = document.querySelector('#page-content');
    if(!page) return;
    const board = boards.find(b=>b.id===selectedBoardId);
    if(loading) { page.innerHTML = `<section class="tracker-loading"><span class="tracker-spinner"></span><p>Opening your team boards…</p></section>`; return; }
    if(loadError) { page.innerHTML = `<section class="tracker-empty"><div class="tracker-empty-icon">!</div><h2>Boards aren’t available yet</h2><p>${esc(loadError)}</p><button class="button-primary" data-tracker="refresh">Try again</button></section>`; return; }
    if(!boards.length) {
      page.innerHTML = `<div class="tracker-heading"><div><div class="eyebrow">${esc(currentWorkspace.name)} · TEAM TRACKER</div><h1>Make work visible.</h1><p>Give your team a shared place to move projects forward.</p></div></div><section class="tracker-empty"><div class="tracker-empty-icon">▦</div><h2>Start with a board</h2><p>Boards give a project a home. Add a few stages, then invite your team into the work.</p><button class="button-primary" data-tracker="new-board">Create your first board <span>→</span></button></section>`;
      return;
    }
    page.innerHTML = `<div class="tracker-heading"><div><div class="eyebrow">${esc(currentWorkspace.name)} · TEAM TRACKER</div><h1>${esc(board?.name||'Team board')}</h1><p>${esc(board?.description||'A clear view of what’s moving and who’s on it.')}</p></div><div class="tracker-heading-actions"><button class="button-secondary" data-tracker="edit-board">Board settings</button><button class="button-primary" data-tracker="new-board">＋ New board</button></div></div>
    <div class="board-toolbar"><div class="board-tabs" role="tablist" aria-label="Boards">${boards.map(b=>`<button class="board-tab ${b.id===selectedBoardId?'selected':''}" role="tab" aria-selected="${b.id===selectedBoardId}" data-board="${esc(b.id)}">${esc(b.name)}</button>`).join('')}</div><div class="board-meta"><span class="member-stack">${members.slice(0,5).map((m,i)=>`<span class="member-avatar member-tone-${i%5}" title="${esc(m.email||'Team member')}">${esc((m.email||'T').slice(0,1).toUpperCase())}</span>`).join('')}</span><span>${members.length} ${members.length===1?'member':'members'}</span><button class="text-link" data-page="members">View team →</button></div></div>
    <section class="board-canvas" aria-label="${esc(board?.name||'Board')} lists">${lists.map((list,idx)=>{
      const listCards=cards.filter(c=>c.list_id===list.id);
      return `<section class="board-list" data-list="${esc(list.id)}"><div class="board-list-head"><div class="list-title-wrap"><span class="list-color list-color-${idx%5}"></span><h2>${esc(list.name)}</h2><span class="list-count">${listCards.length}</span></div><button class="list-menu" data-tracker="edit-list" data-id="${esc(list.id)}" aria-label="List options" title="List options">···</button></div><div class="board-card-stack" data-drop-list="${esc(list.id)}">${listCards.map(card=>`<article class="task-card" draggable="true" data-card="${esc(card.id)}" data-list-id="${esc(list.id)}"><button class="task-card-open" data-tracker="edit-card" data-id="${esc(card.id)}" aria-label="Open ${esc(card.title)}"></button><h3>${esc(card.title)}</h3>${card.description?`<p>${esc(card.description)}</p>`:''}<div class="task-card-foot">${card.due_date?`<span class="task-due">◷ ${esc(dateLabel(card.due_date))}</span>`:'<span></span>'}<span class="task-assignee ${card.assignee_id?'':'unassigned'}" title="${esc(card.assignee_id?memberName(card.assignee_id):'No assignee')}">${esc(card.assignee_id?memberName(card.assignee_id).slice(0,1).toUpperCase():'＋')}</span></div><span class="drag-grip" aria-hidden="true">⠿</span></article>`).join('')}</div><button class="add-task" data-tracker="new-card" data-list="${esc(list.id)}"><span>＋</span> Add a card</button></section>`;
    }).join('')}<button class="add-list" data-tracker="new-list"><span>＋</span><strong>Add another list</strong></button></section>`;
  }
  async function refresh() { await load(); if(currentPage==='members')await renderMembers();else renderBoards(); }
  async function switchBoard(id) { selectedBoardId=id; await load(); renderBoards(); }
  function openForm(kind, item={}) {
    const root=document.querySelector('#modal-root'); if(!root)return;
    const isCard=kind==='card', isList=kind==='list', isBoard=kind==='board';
    const title=isCard?(item.id?'Edit card':'Add a card'):isList?(item.id?'Edit list':'Add a list'):(item.id?'Board settings':'Create a board');
    root.innerHTML=`<div class="modal-backdrop" id="tracker-modal-backdrop"><form class="modal tracker-modal" id="tracker-form" data-item-id="${esc(item.id||'')}"><div class="modal-head"><div><div class="eyebrow">${isCard?'CARD DETAILS':isList?'BOARD LIST':'TEAM BOARD'}</div><h2>${title}</h2></div><button type="button" class="modal-close" data-tracker="close-modal" aria-label="Close">×</button></div><label class="input-label" for="tracker-title">${isCard?'Card title':isList?'List name':'Board name'}</label><input class="field" id="tracker-title" maxlength="${isCard?180:isList?80:100}" value="${esc(item.title||item.name||'')}" placeholder="${isCard?'What needs to get done?':isList?'e.g. In progress':'e.g. Website refresh'}" required>${isBoard?`<label class="input-label" for="tracker-description" style="margin-top:15px">Description <span class="optional-label">Optional</span></label><textarea class="textarea" id="tracker-description" rows="3" maxlength="500" placeholder="A little context for the team">${esc(item.description||'')}</textarea>`:''}${isCard?`<label class="input-label" for="tracker-card-description" style="margin-top:15px">Details <span class="optional-label">Optional</span></label><textarea class="textarea" id="tracker-card-description" rows="4" maxlength="3000" placeholder="Add useful context, links, or acceptance notes">${esc(item.description||'')}</textarea><div class="tracker-form-row"><div><label class="input-label" for="tracker-assignee">Assigned to</label><select class="select" id="tracker-assignee">${memberPicker(item.assignee_id||'')}</select></div><div><label class="input-label" for="tracker-due">Due date <span class="optional-label">Optional</span></label><input class="field" id="tracker-due" type="date" value="${esc(item.due_date||'')}"></div></div>`:''}<div class="modal-actions">${item.id?'<button class="button-secondary tracker-delete" type="button" data-tracker="delete-item" data-kind="'+kind+'">Delete</button>':''}<button class="button-secondary" type="button" data-tracker="close-modal">Cancel</button><button class="button-primary" type="submit">${item.id?'Save changes':isCard?'Add card':isList?'Add list':'Create board'}</button></div><div class="tracker-form-error" id="tracker-form-error" role="alert"></div></form></div>`;
    root.querySelector('#tracker-modal-backdrop').onclick=e=>{if(e.target.id==='tracker-modal-backdrop')root.innerHTML=''};
    root.querySelector('#tracker-form').onsubmit=async e=>{
      e.preventDefault(); const saveButton=e.currentTarget.querySelector('[type="submit"]'); saveButton.disabled=true;
      try {
        const name=root.querySelector('#tracker-title').value.trim();
        if(isBoard) {
          const values={name,description:root.querySelector('#tracker-description').value.trim(),updated_at:new Date().toISOString()};
          if(item.id) await update(db.from('team_boards').update(values).eq('id',item.id).eq('organization_id',currentWorkspace.organization_id),'Board updated.');
          else {const {data,error}=await db.rpc('create_team_board',{p_organization_id:currentWorkspace.organization_id,p_name:name,p_description:values.description});if(error)throw error;selectedBoardId=data;localStorage.setItem(trackerKey(),data);toast('Board created with To do, In progress and Done lists.');}
        } else if(isList) {
          if(item.id) await update(db.from('team_board_lists').update({name}).eq('id',item.id).eq('board_id',selectedBoardId),'List renamed.');
          else await update(db.from('team_board_lists').insert({organization_id:currentWorkspace.organization_id,board_id:selectedBoardId,name,position:lists.length?Math.max(...lists.map(l=>Number(l.position)))+1:0}),'List added.');
        } else {
          const values={title:name,description:root.querySelector('#tracker-card-description').value.trim(),assignee_id:root.querySelector('#tracker-assignee').value||null,due_date:root.querySelector('#tracker-due').value||null,updated_at:new Date().toISOString()};
          if(item.id) await update(db.from('team_board_cards').update(values).eq('id',item.id).eq('board_id',selectedBoardId),'Card updated.');
          else {const listId=item.list_id;const count=cards.filter(c=>c.list_id===listId).length;await update(db.from('team_board_cards').insert({...values,organization_id:currentWorkspace.organization_id,board_id:selectedBoardId,list_id:listId,position:count,created_by:currentUser.id}),'Card added.');}
        }
        root.innerHTML=''; await refresh();
      } catch(error) { const el=root.querySelector('#tracker-form-error');el.textContent=error.message||'Could not save that change.';saveButton.disabled=false; }
    };
  }
  async function deleteItem(kind,id) {
    if(!window.confirm(kind==='board'?'Delete this board and all of its lists and cards?':kind==='list'?'Delete this list and all cards in it?':'Delete this card?'))return;
    try {
      const table=kind==='board'?'team_boards':kind==='list'?'team_board_lists':'team_board_cards';
      let q=db.from(table).delete().eq('id',id).eq('organization_id',currentWorkspace.organization_id);
      if(kind==='board') { boards=boards.filter(b=>b.id!==id);if(selectedBoardId===id)selectedBoardId=null; }
      if(kind==='list') q=q.eq('board_id',selectedBoardId);
      if(kind==='card') q=q.eq('board_id',selectedBoardId);
      await update(q,kind==='board'?'Board deleted.':kind==='list'?'List deleted.':'Card deleted.');
      document.querySelector('#modal-root').innerHTML='';await refresh();
    } catch(error) { toast(error.message||'Could not delete that item.');await refresh(); }
  }
  async function renderMembers() {
    const page=document.querySelector('#page-content');
    if(loadedOrgId!==currentWorkspace.organization_id || !members.length) { page.innerHTML='<section class="tracker-loading"><span class="tracker-spinner"></span><p>Loading your team…</p></section>';await load(); }
    if(loadError){page.innerHTML=`<section class="tracker-empty"><div class="tracker-empty-icon">!</div><h2>Team details aren’t available</h2><p>${esc(loadError)}</p><button class="button-primary" data-tracker="refresh">Try again</button></section>`;return;}
    const canInvite=['owner','admin'].includes(currentWorkspace.role);
    page.innerHTML=`<div class="tracker-heading"><div><div class="eyebrow">${esc(currentWorkspace.name)} · PEOPLE</div><h1>Your team</h1><p>People working together in this workspace.</p></div>${canInvite?'<button class="button-primary" data-workspace-manage>Invite a teammate <span>→</span></button>':''}</div><section class="team-members-grid">${members.map((m,i)=>`<article class="team-member-card"><span class="member-avatar member-avatar-large member-tone-${i%5}">${esc((m.email||'T').slice(0,1).toUpperCase())}</span><div><strong>${esc(m.email?.split('@')[0]||'Team member')}</strong><small>${esc(m.email||'')}</small></div><span class="member-role">${esc(m.role)}</span></article>`).join('')}</section>`;
  }
  async function renderAuditLog() {
    const page=document.querySelector('#page-content');
    if(currentWorkspace?.role!=='owner'){page.innerHTML='<section class="tracker-empty"><div class="tracker-empty-icon">◷</div><h2>Owner access only</h2><p>Workspace audit history is visible only to the workspace owner.</p></section>';return;}
    page.innerHTML='<section class="tracker-loading"><span class="tracker-spinner"></span><p>Loading owner audit history…</p></section>';
    const {data,error}=await db.from('organization_audit_logs').select('id,actor_email,action,entity_type,entity_id,before_data,after_data,occurred_at').eq('organization_id',currentWorkspace.organization_id).order('occurred_at',{ascending:false}).limit(200);
    if(error){page.innerHTML=`<section class="tracker-empty"><div class="tracker-empty-icon">!</div><h2>Audit history isn’t available</h2><p>${esc(/PGRST|does not exist|schema cache/i.test(error.message||'')?'Apply the latest supabase/schema.sql in the connected Supabase project, then reload.':error.message)}</p><button class="button-primary" data-tracker="audit-refresh">Try again</button></section>`;return;}
    const label=x=>{const row=x.after_data||x.before_data||{};return row.name||row.title||row.email||row.invited_email||row.requested_email||row.role||x.entity_id||'Workspace record'};
    const summary=x=>{const before=x.before_data||{},after=x.after_data||{};if(x.action==='INSERT')return `Created ${label(x)}`;if(x.action==='DELETE')return `Deleted ${label(x)}`;const changed=Object.keys(after).filter(k=>!['updated_at'].includes(k)&&JSON.stringify(after[k])!==JSON.stringify(before[k]));return `Updated ${label(x)}${changed.length?` · ${changed.slice(0,4).join(', ').replaceAll('_',' ')}`:''}`};
    page.innerHTML=`<div class="tracker-heading"><div><div class="eyebrow">${esc(currentWorkspace.name)} · OWNER ONLY</div><h1>Workspace audit log</h1><p>Recent changes across members, invitations, departments, and team boards. Only the owner can read this history.</p></div><button class="button-secondary" data-tracker="audit-refresh">Refresh</button></div><section class="audit-timeline">${data?.length?data.map(x=>`<article class="audit-entry"><span class="audit-marker">${x.action==='DELETE'?'−':x.action==='INSERT'?'+':'↻'}</span><div class="audit-entry-main"><strong>${esc(summary(x))}</strong><small>${esc(x.entity_type.replaceAll('_',' '))} · ${esc(x.actor_email||'Workspace system')}</small></div><time datetime="${esc(x.occurred_at)}">${esc(new Date(x.occurred_at).toLocaleString(undefined,{dateStyle:'medium',timeStyle:'short'}))}</time></article>`).join(''):'<div class="audit-empty"><span class="audit-empty-icon" aria-hidden="true">✓</span><strong>Audit history is ready</strong><span>It starts recording changes from now on; earlier activity isn’t backfilled. Create or update a board, invite a teammate, or make another workspace change to see the first entry.</span></div>'}</section><p class="audit-retention">Showing the latest ${data?.length||0} changes.</p>`;
  }
  document.addEventListener('click',async e=>{
    const boardTab=e.target.closest('[data-board]');if(boardTab){await switchBoard(boardTab.dataset.board);return;}
    const action=e.target.closest('[data-tracker]')?.dataset.tracker;if(!action)return;
    const btn=e.target.closest('[data-tracker]');
    if(action==='refresh')return refresh();
    if(action==='audit-refresh')return renderAuditLog();
    if(action==='new-board')return openForm('board');
    if(action==='edit-board')return openForm('board',boards.find(b=>b.id===selectedBoardId)||{});
    if(action==='new-list')return openForm('list');
    if(action==='edit-list')return openForm('list',lists.find(l=>l.id===btn.dataset.id)||{});
    if(action==='new-card')return openForm('card',{list_id:btn.dataset.list});
    if(action==='edit-card')return openForm('card',cards.find(c=>c.id===btn.dataset.id)||{});
    if(action==='close-modal'){document.querySelector('#modal-root').innerHTML='';return;}
    if(action==='delete-item')return deleteItem(btn.dataset.kind,document.querySelector('#tracker-form')?.dataset.itemId);
  });
  document.addEventListener('dragstart',e=>{const card=e.target.closest('.task-card');if(!card)return;e.dataTransfer.setData('text/plain',card.dataset.card);e.dataTransfer.effectAllowed='move';requestAnimationFrame(()=>card.classList.add('is-dragging'));});
  document.addEventListener('dragend',e=>e.target.closest('.task-card')?.classList.remove('is-dragging'));
  document.addEventListener('dragover',e=>{const target=e.target.closest('[data-drop-list]');if(target){e.preventDefault();target.classList.add('is-drop-target');}});
  document.addEventListener('dragleave',e=>e.target.closest('[data-drop-list]')?.classList.remove('is-drop-target'));
  document.addEventListener('drop',async e=>{
    const target=e.target.closest('[data-drop-list]');if(!target)return;e.preventDefault();target.classList.remove('is-drop-target');
    const cardId=e.dataTransfer.getData('text/plain'),card=cards.find(c=>c.id===cardId),newListId=target.dataset.dropList;if(!card||!newListId)return;
    const sibling=e.target.closest('.task-card'),targetCards=cards.filter(c=>c.list_id===newListId&&c.id!==cardId);let position=targetCards.length;
    if(sibling){const idx=targetCards.findIndex(c=>c.id===sibling.dataset.card);if(idx>=0)position=idx;}
    const oldListId=card.list_id;card.list_id=newListId;renderBoards();
    try { const {error}=await db.rpc('move_team_board_card',{p_card_id:cardId,p_target_list_id:newListId,p_position:position});if(error)throw error; }
    catch(error) { card.list_id=oldListId;toast(error.message||'Could not move that card.'); }
    await refresh();
  });
  return {render:async page=>{if(!currentWorkspace)return;currentPage=page;const content=document.querySelector('#page-content');if(content)content.innerHTML='<section class="tracker-loading"><span class="tracker-spinner"></span><p>Opening your team workspace…</p></section>';if(page==='audit'){await renderAuditLog();return;}if(page==='members'){await renderMembers();return;}await load();renderBoards();}};
})();
function renderTeamTracker(page='boards') { return teamTracker.render(page); }
