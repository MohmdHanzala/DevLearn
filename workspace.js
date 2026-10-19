function updateWorkspaceLabels(){
  const name=currentWorkspace?.name||'Personal workspace';
  const label=document.querySelector('#workspace-current');if(label)label.textContent=name.toUpperCase();
  const profile=document.querySelector('.profile-name');if(profile)profile.innerHTML=`${esc(currentUser?.email?.split('@')[0]||'Developer')}<small>${esc(name)}</small>`;
  const initials=(currentUser?.email?.split('@')[0]||'DL').slice(0,2).toUpperCase();
  document.querySelectorAll('.profile .avatar,.small-avatar').forEach(el=>el.textContent=initials);
}

async function switchWorkspace(organizationId){
  currentWorkspace=workspaceMemberships.find(w=>w.organization_id===organizationId)||null;
  if(currentWorkspace)localStorage.setItem('devlearn-workspace',currentWorkspace.organization_id);else localStorage.removeItem('devlearn-workspace');
  updateWorkspaceLabels();
  try{await loadUserNotes()}catch(error){notes=[];toast('Could not load notes for this workspace. Check the database schema.');}
  render(activePage);openWorkspaceManager();
}

function openWorkspaceManager(){
  const root=document.querySelector('#modal-root');
  if(!db||!currentUser){toast('Sign in to manage workspaces.');return}
  const choices=[{organization_id:'',name:'Personal workspace',role:'personal',departmentName:'Private notes'},...workspaceMemberships];
  const choiceMarkup=choices.map(w=>`<button class="workspace-choice ${((currentWorkspace?.organization_id||'')===w.organization_id)?'selected':''}" data-workspace-choice="${esc(w.organization_id)}"><span><strong>${esc(w.name)}</strong><small>${esc(w.organization_id?w.departmentName+' · '+w.role:'Private to your account')}</small></span><span>→</span></button>`).join('');
  root.innerHTML=`<div class="modal-backdrop" id="workspace-backdrop"><section class="modal workspace-modal" role="dialog" aria-modal="true" aria-labelledby="workspace-title"><div class="modal-head"><div><h2 id="workspace-title">Your workspaces</h2><p>Keep personal learning private, or share verified notes with a team.</p></div><button class="modal-close" id="workspace-close" aria-label="Close">×</button></div><div class="workspace-choice-list">${choiceMarkup}</div><div class="workspace-create-grid"><div><label class="input-label" for="workspace-name">Create a company or team workspace</label><div class="workspace-inline"><input class="field" id="workspace-name" maxlength="120" placeholder="e.g. Northwind Engineering"><button class="button-primary" id="workspace-create">Create</button></div></div><div><label class="input-label" for="workspace-code">Join with an invitation code</label><div class="workspace-inline"><input class="field" id="workspace-code" maxlength="80" placeholder="Paste a team invite code"><button class="button-secondary" id="workspace-join">Join</button></div></div></div><div id="workspace-message" class="workspace-message" aria-live="polite"></div>${currentWorkspace&&['owner','admin'].includes(currentWorkspace.role)?`<div class="workspace-admin"><div class="panel-heading"><h3>Workspace administration</h3><span class="review-num">Owners and admins</span></div><label class="input-label" for="workspace-department">Add a department</label><div class="workspace-inline"><input class="field" id="workspace-department" maxlength="100" placeholder="Engineering, Finance, Operations"><button class="button-secondary" id="workspace-add-department">Add department</button></div><label class="input-label" for="workspace-invite-dept">Create an invite for</label><div class="workspace-inline"><select class="select" id="workspace-invite-dept"><option value="">All departments</option></select><input class="field" id="workspace-invite-domain" placeholder="Email domain (optional)"><button class="button-primary" id="workspace-create-invite">Create invite</button></div><p class="workspace-help">Leave the domain blank to let colleagues join from any email domain. Invite codes expire after 14 days.</p><div id="workspace-invite-result"></div></div>`:''}</section></div>`;
  const close=()=>{root.innerHTML=''};
  document.querySelector('#workspace-close').onclick=close;
  document.querySelector('#workspace-backdrop').onclick=e=>{if(e.target.id==='workspace-backdrop')close()};
  root.querySelectorAll('[data-workspace-choice]').forEach(button=>button.onclick=async()=>{await switchWorkspace(button.dataset.workspaceChoice||null)});
  const message=root.querySelector('#workspace-message');
  const showError=error=>{message.textContent=error.message||'Could not complete this workspace action.';message.classList.add('error')};
  root.querySelector('#workspace-create').onclick=async()=>{const name=root.querySelector('#workspace-name').value.trim();if(name.length<2){message.textContent='Enter a workspace name with at least 2 characters.';message.classList.add('error');return}try{const {data,error}=await db.rpc('create_workspace',{p_name:name});if(error)throw error;localStorage.setItem('devlearn-workspace',data);await signedIn(currentUser);openWorkspaceManager()}catch(error){showError(error)}};
  root.querySelector('#workspace-join').onclick=async()=>{const code=root.querySelector('#workspace-code').value.trim();if(!code){message.textContent='Paste the invitation code first.';message.classList.add('error');return}try{const {data,error}=await db.rpc('join_workspace',{p_code:code});if(error)throw error;localStorage.setItem('devlearn-workspace',data);await signedIn(currentUser);openWorkspaceManager()}catch(error){showError(error)}};
  if(currentWorkspace&&['owner','admin'].includes(currentWorkspace.role)){
    const deptSelect=root.querySelector('#workspace-invite-dept');
    db.from('departments').select('id,name').eq('organization_id',currentWorkspace.organization_id).order('name').then(({data,error})=>{if(error)return;for(const dept of data||[]){const option=document.createElement('option');option.value=dept.id;option.textContent=dept.name;deptSelect.append(option)}});
    root.querySelector('#workspace-add-department').onclick=async()=>{const name=root.querySelector('#workspace-department').value.trim();if(name.length<2){message.textContent='Enter a department name with at least 2 characters.';message.classList.add('error');return}try{const {error}=await db.rpc('create_workspace_department',{p_organization_id:currentWorkspace.organization_id,p_name:name});if(error)throw error;toast('Department added.');openWorkspaceManager()}catch(error){showError(error)}};
    root.querySelector('#workspace-create-invite').onclick=async()=>{const departmentId=deptSelect.value||null;const domain=root.querySelector('#workspace-invite-domain').value.trim().toLowerCase()||null;try{const {data,error}=await db.rpc('create_workspace_invite',{p_organization_id:currentWorkspace.organization_id,p_department_id:departmentId,p_email_domain:domain});if(error)throw error;const result=root.querySelector('#workspace-invite-result');result.innerHTML=`<div class="invite-result"><div><small>Share this one-time invitation code · valid for 14 days</small><code>${esc(data)}</code></div><button class="button-secondary" id="workspace-copy-invite">Copy code</button></div>`;root.querySelector('#workspace-copy-invite').onclick=async()=>{try{await navigator.clipboard.writeText(data);toast('Invitation code copied.')}catch{toast('Select and copy the invitation code.')}}}catch(error){showError(error)}};
  }
}
