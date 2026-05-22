import { createClient } from '@supabase/supabase-js';
import './styles.css';

const cfg = {
  url: import.meta.env.VITE_SUPABASE_URL,
  key: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,
  appName: import.meta.env.VITE_APP_NAME || 'RideMate',
  supportPhone: import.meta.env.VITE_SUPPORT_PHONE || '03000000000',
};

if (!cfg.url || !cfg.key) {
  document.querySelector('#app').innerHTML = `<div class="auth"><div class="card"><div class="h1">Setup required</div><p class="muted">Add VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY in Netlify environment variables, then redeploy.</p></div></div>`;
  throw new Error('Missing Supabase environment variables');
}

const supabase = createClient(cfg.url, cfg.key, { auth: { persistSession: true, autoRefreshToken: true } });

const state = {
  session: null,
  profile: null,
  privateProfile: null,
  tab: 'home',
  rides: [],
  myBookings: [],
  myRides: [],
  requests: [],
  vehicles: [],
  reports: [],
  users: [],
  savedRoutes: [],
  notifications: [],
  authMode: 'login',
  authNotice: '',
  appError: '',
  modal: null,
  loading: false,
  filters: { from: '', to: '', ride_rule: 'safe', date: today() },
};



const ROUTE_PRESETS = [
  {code:'WAH-ISB-BLUE', name:'Wah Cantt → Islamabad Blue Area', from:'Wah Cantt', to:'Islamabad', pickup:'Wah Cantt Barrier 2 / GT Road', dropoff:'Blue Area / PIMS / F-8', via:'GT Road → Taxila → Margalla Road/Golra → G-9/G-8 → Blue Area', distance:'36–60 km depending pickup', time:'35–70 min'},
  {code:'WAH-ISB-G13', name:'Wah Cantt → Islamabad G-13/G-11', from:'Wah Cantt', to:'Islamabad', pickup:'Wah Model Town / Barrier 2', dropoff:'G-13 / G-11 / NUST side', via:'GT Road → Taxila → Golra Mor → Srinagar/Margalla side', distance:'35–50 km', time:'35–60 min'},
  {code:'WAH-ISB-I8', name:'Wah Cantt → Islamabad I-8/I-9', from:'Wah Cantt', to:'Islamabad', pickup:'Wah Cantt Gate/Barrier', dropoff:'I-8 / I-9 / Faizabad', via:'GT Road → Rawalpindi/Islamabad link → IJP/Faizabad', distance:'45–60 km', time:'50–85 min'},
  {code:'WAH-RWP-SADDAR', name:'Wah Cantt → Rawalpindi Saddar', from:'Wah Cantt', to:'Rawalpindi', pickup:'Wah Cantt Barrier 2 / Lala Rukh / Taxila', dropoff:'Saddar / MH / RA Bazar', via:'GT Road → Taxila → Tarnol/Chungi → Rawalpindi Saddar', distance:'35–45 km', time:'35–65 min'},
  {code:'WAH-RWP-FAIZABAD', name:'Wah Cantt → Rawalpindi/Faizabad', from:'Wah Cantt', to:'Rawalpindi', pickup:'Wah Model Town / New City / Taxila', dropoff:'Faizabad / Murree Road / Shamsabad', via:'GT Road → IJP Road/Faizabad corridor', distance:'45–60 km', time:'50–90 min'},
  {code:'RWP-ISB-BLUE', name:'Rawalpindi → Islamabad Blue Area', from:'Rawalpindi', to:'Islamabad', pickup:'Saddar / Murree Road / Faizabad', dropoff:'Blue Area / G-8 / F-8', via:'Murree Road/Faizabad → Islamabad Expressway/Zero Point → Blue Area', distance:'15–25 km', time:'25–60 min'},
  {code:'RWP-ISB-I8', name:'Rawalpindi → Islamabad I-8/I-9', from:'Rawalpindi', to:'Islamabad', pickup:'Commercial Market / Saddar / Faizabad', dropoff:'I-8 / I-9 / I-10', via:'Murree Road/Faizabad → IJP/I-8 corridor', distance:'10–20 km', time:'20–45 min'},
  {code:'ISB-WAH-EVENING', name:'Islamabad → Wah Cantt Evening Return', from:'Islamabad', to:'Wah Cantt', pickup:'Blue Area / F-8 / G-9 / G-13', dropoff:'Wah Cantt Barrier 2 / Wah Model Town', via:'Islamabad sectors → Golra/Margalla Road or GT Road → Taxila → Wah', distance:'36–60 km', time:'45–90 min'},
  {code:'RWP-WAH-EVENING', name:'Rawalpindi → Wah Cantt Evening Return', from:'Rawalpindi', to:'Wah Cantt', pickup:'Saddar / RA Bazar / Faizabad', dropoff:'Wah Cantt / Taxila / New City', via:'Rawalpindi → GT Road → Taxila → Wah Cantt', distance:'35–60 km', time:'45–90 min'}
];

function routeDatalist(){
  return `<datalist id="routeCities"><option>Wah Cantt</option><option>Taxila</option><option>Rawalpindi</option><option>Islamabad</option><option>Blue Area</option><option>G-13 Islamabad</option><option>G-11 Islamabad</option><option>F-8 Islamabad</option><option>I-8 Islamabad</option><option>Faizabad</option><option>Saddar Rawalpindi</option><option>RA Bazar Rawalpindi</option></datalist>`;
}
function routePresetOptions(){ return ROUTE_PRESETS.map(r=>`<option value="${esc(r.code)}">${esc(r.name)}</option>`).join(''); }
function routePresetCards(){
  return ROUTE_PRESETS.slice(0,6).map(r=>`<button class="routePreset" data-route-preset="${esc(r.code)}"><b>${esc(r.name)}</b><span>${esc(r.via)}</span><small>${esc(r.time)}</small></button>`).join('');
}
function findPreset(code){ return ROUTE_PRESETS.find(r=>r.code===code); }
function routeSummary(r){ return [r.route_name, r.trip_type, r.recurrence_type && r.recurrence_type !== 'once' ? r.recurrence_type : '', r.allow_monthly_booking ? 'monthly seats' : ''].filter(Boolean).join(' · '); }

const $ = (sel) => document.querySelector(sel);
const app = $('#app');
window.addEventListener('error', (event) => showAppError(event.message || 'Unexpected app error'));
window.addEventListener('unhandledrejection', (event) => showAppError(event.reason?.message || 'Unexpected app error'));
function showAppError(message){
  if (!app) return;
  app.innerHTML = `<div class="auth"><div class="card"><div class="h1">App could not load</div><p class="muted">${esc(message)}</p><div class="alert">Try clearing browser cache, then redeploy from Netlify without cache. If this remains, check Supabase URL/key and SQL migrations.</div></div></div>`;
}
const money = (n) => `Rs. ${Number(n || 0).toLocaleString('en-PK')}`;
const fmt = (dt) => new Date(dt).toLocaleString('en-PK', { dateStyle: 'medium', timeStyle: 'short' });
function today(){ return new Date().toISOString().slice(0,10); }
function toast(msg){ const t=document.createElement('div'); t.className='toast'; t.textContent=msg; document.body.appendChild(t); setTimeout(()=>t.remove(),3000); }
function esc(x=''){ return String(x ?? '').replace(/[&<>'"]/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[m])); }
function role(){ return state.profile?.role || 'passenger'; }
function isAdmin(){ return state.profile?.role === 'admin'; }
function setTab(t){ state.tab=t; render(); if(state.session) loadData(); }

supabase.auth.onAuthStateChange((_event, session) => {
  state.session = session;
  init();
});

init();

async function init(){
  try {
    const { data } = await supabase.auth.getSession();
    state.session = data.session;
    if (!state.session) return renderAuth();
    const ok = await loadMe();
    if (!ok) return;
    await loadData();
    render();
    subscribeRealtime();
  } catch (err) {
    showAppError(err.message || 'App initialization failed');
  }
}

async function loadMe(){
  const uid = state.session.user.id;
  const [p, pp] = await Promise.all([
    supabase.from('profiles').select('*').eq('id', uid).maybeSingle(),
    supabase.from('private_profiles').select('*').eq('user_id', uid).maybeSingle(),
  ]);
  if (p.error) throw new Error(`Profile load failed: ${p.error.message}`);
  if (pp.error) throw new Error(`Private profile load failed: ${pp.error.message}`);
  state.profile = p.data;
  state.privateProfile = pp.data;
  if (!state.profile) {
    await supabase.auth.signOut();
    state.authMode = 'signup';
    state.authNotice = 'Profile was not created. Please sign up again, or check that schema.sql trigger was run in Supabase.';
    renderAuth();
    return false;
  }
  return true;
}

async function loadData(){
  if (!state.session || !state.profile) return;
  const uid = state.session.user.id;
  const fromDate = new Date(); fromDate.setHours(0,0,0,0);
  const qRides = supabase.from('rides_public').select('*').eq('status','open').gte('departure_at', fromDate.toISOString()).order('departure_at',{ascending:true}).limit(100);
  const qBookings = supabase.from('bookings_public').select('*').or(`passenger_id.eq.${uid},driver_id.eq.${uid}`).order('created_at',{ascending:false}).limit(100);
  const qVehicles = isAdmin() ? supabase.from('vehicles').select('*, profiles(full_name)').order('created_at',{ascending:false}) : supabase.from('vehicles').select('*').eq('owner_id',uid).order('created_at',{ascending:false});
  const qMyRides = supabase.from('rides_public').select('*').eq('driver_id',uid).order('departure_at',{ascending:false}).limit(100);
  const qSavedRoutes = supabase.from('saved_routes').select('*').eq('user_id',uid).order('created_at',{ascending:false}).limit(50);
  const qNotifications = supabase.from('notifications').select('*').eq('user_id',uid).order('created_at',{ascending:false}).limit(20);
  const promises = [qRides, qBookings, qVehicles, qMyRides, qSavedRoutes, qNotifications];
  if (isAdmin()) {
    promises.push(supabase.rpc('admin_dashboard'));
    promises.push(supabase.from('reports_public').select('*').order('created_at',{ascending:false}).limit(100));
    promises.push(supabase.from('profiles').select('*').order('created_at',{ascending:false}).limit(100));
  }
  const res = await Promise.all(promises);
  const firstError = res.find(x => x.error)?.error;
  if (firstError) throw new Error(`Database query failed: ${firstError.message}`);
  state.rides = res[0].data || [];
  state.myBookings = (res[1].data || []).filter(b => b.passenger_id === uid);
  state.requests = (res[1].data || []).filter(b => b.driver_id === uid);
  state.vehicles = res[2].data || [];
  state.myRides = res[3].data || [];
  state.savedRoutes = res[4].data || [];
  state.notifications = res[5].data || [];
  if (isAdmin()) { state.admin = res[6].data || {}; state.reports = res[7].data || []; state.users = res[8].data || []; }
}

let channel;
function subscribeRealtime(){
  if (channel) return;
  channel = supabase.channel('ridemate-live')
    .on('postgres_changes',{event:'*',schema:'public',table:'rides'},() => loadData().then(render))
    .on('postgres_changes',{event:'*',schema:'public',table:'bookings'},() => loadData().then(render))
    .on('postgres_changes',{event:'*',schema:'public',table:'reports'},() => isAdmin() && loadData().then(render))
    .subscribe();
}

function renderAuth(){
  const isSignup = state.authMode === 'signup';
  app.innerHTML = `<div class="auth"><div class="hero"><img class="heroLogo" src="/branding/logo-horizontal.png" alt="RideMate logo" /><div class="pill ok">Pakistan Carpool</div><div class="h1">Ride sharing with safety, seats & rules.</div><p>Drivers post rides. Passengers book seats. Admin controls reports and users.</p></div><div class="card authCard"><div class="authTabs"><button class="authTab ${!isSignup?'active':''}" id="showLogin" type="button">Login</button><button class="authTab ${isSignup?'active':''}" id="showSignup" type="button">Sign up</button></div>${state.authNotice ? `<div class="success">${esc(state.authNotice)}</div>` : ''}${!isSignup ? `<div class="h2">Welcome back</div><p class="small muted">Login with your registered email and password.</p><form id="loginForm" class="grid"><label>Email<input name="email" type="email" required placeholder="you@email.com"></label><label>Password<input name="password" type="password" required placeholder="minimum 6 characters"></label><button class="btn green">Login</button></form><p class="small muted">New user? Tap Sign up above.</p>` : `<div class="h2">Create account</div><p class="small muted">Register as passenger or driver. Admin role is assigned from Supabase only.</p><form id="signupForm" class="grid"><label>Full name<input name="full_name" required placeholder="Mustafa Ali"></label><label>Email<input name="email" type="email" required placeholder="you@email.com"></label><label>Password<input name="password" type="password" minlength="6" required placeholder="minimum 6 characters"></label><div class="grid2"><label>Role<select name="role"><option value="passenger">Passenger</option><option value="driver">Driver</option></select></label><label>Gender<select name="gender"><option value="male">Male</option><option value="female">Female</option></select></label></div><label>Phone<input name="phone" required placeholder="03000000000"></label><button class="btn">Create account</button></form>`}</div></div>`;
  $('#showLogin').onclick = () => { state.authMode='login'; state.authNotice=''; renderAuth(); };
  $('#showSignup').onclick = () => { state.authMode='signup'; state.authNotice=''; renderAuth(); };
  const loginForm = $('#loginForm');
  if (loginForm) loginForm.onsubmit = async (e) => { e.preventDefault(); const f=Object.fromEntries(new FormData(e.target)); const {error}=await supabase.auth.signInWithPassword(f); if(error) toast(error.message); };
  const signupForm = $('#signupForm');
  if (signupForm) signupForm.onsubmit = async (e) => { e.preventDefault(); const f=Object.fromEntries(new FormData(e.target)); const {error}=await supabase.auth.signUp({ email:f.email, password:f.password, options:{ data:{ full_name:f.full_name, role:f.role, gender:f.gender, phone:f.phone }}}); if(error) toast(error.message); else { state.authMode='login'; state.authNotice='Registered successfully. Please check your email confirmation link, then login.'; renderAuth(); } };
}

function render(){
  if (!state.session) return renderAuth();
  const tabs = navTabs();
  app.innerHTML = `<div class="shell"><div class="top"><div class="brand"><div class="row"><img class="topLogo" src="/icons/icon-192.png" alt="RideMate" /><div><div class="title">${cfg.appName}</div><div class="sub">${esc(state.profile?.full_name)} · ${esc(role())}</div></div></div><button class="avatar" id="logoutBtn">Logout</button></div></div><main class="content">${view()}</main>${state.modal || ''}<nav class="tabs">${tabs.map(t=>`<button class="tab ${state.tab===t.id?'active':''}" data-tab="${t.id}">${t.icon}<br>${t.label}</button>`).join('')}</nav></div>`;
  $('#logoutBtn').onclick=()=>supabase.auth.signOut();
  document.querySelectorAll('[data-tab]').forEach(b=>b.onclick=()=>setTab(b.dataset.tab));
  bindViewEvents();
}

function navTabs(){
  if (isAdmin()) return [{id:'home',label:'Admin',icon:'📊'},{id:'adminUsers',label:'Users',icon:'👥'},{id:'adminRides',label:'Rides',icon:'🚗'},{id:'safety',label:'Reports',icon:'🛟'},{id:'profile',label:'Profile',icon:'⚙️'}];
  if (role()==='driver') return [{id:'home',label:'Home',icon:'🏠'},{id:'create',label:'Post',icon:'➕'},{id:'requests',label:'Requests',icon:'📩'},{id:'routes',label:'Routes',icon:'🧭'},{id:'profile',label:'Profile',icon:'⚙️'}];
  return [{id:'home',label:'Search',icon:'🔎'},{id:'bookings',label:'Bookings',icon:'🎫'},{id:'routes',label:'Routes',icon:'🧭'},{id:'safety',label:'Safety',icon:'🛟'},{id:'profile',label:'Profile',icon:'⚙️'}];
}

function view(){
  if (isAdmin()) return adminView();
  if (state.tab==='home') return role()==='driver' ? driverHome() : passengerHome();
  if (state.tab==='create') return createRideView();
  if (state.tab==='bookings') return bookingsView();
  if (state.tab==='routes') return routesView();
  if (state.tab==='requests') return requestsView();
  if (state.tab==='safety') return safetyView();
  if (state.tab==='profile') return profileView();
  return passengerHome();
}

function compatible(ride){
  if (ride.driver_id === state.session.user.id) return {ok:false, msg:'Your own ride'};
  if (ride.seats_left <= 0) return {ok:false, msg:'Seats full'};
  const g = state.profile.gender, travel = state.profile.travel_mode;
  if (ride.ride_rule === 'male_only' && g !== 'male') return {ok:false,msg:'Male passengers only'};
  if (ride.ride_rule === 'female_only' && g !== 'female') return {ok:false,msg:'Female passengers only'};
  if (ride.ride_rule === 'family_only' && travel !== 'family') return {ok:false,msg:'Family profile required'};
  return {ok:true,msg:'Safe match'};
}

function passengerHome(){
  let rides = state.rides.filter(r => r.driver_id !== state.session.user.id);
  if (state.filters.from) rides = rides.filter(r => r.from_city.toLowerCase().includes(state.filters.from.toLowerCase()) || r.pickup_area?.toLowerCase().includes(state.filters.from.toLowerCase()));
  if (state.filters.to) rides = rides.filter(r => r.to_city.toLowerCase().includes(state.filters.to.toLowerCase()) || r.dropoff_area?.toLowerCase().includes(state.filters.to.toLowerCase()));
  if (state.filters.ride_rule === 'safe') rides = rides.filter(r => compatible(r).ok);
  else if (state.filters.ride_rule !== 'all') rides = rides.filter(r => r.ride_rule === state.filters.ride_rule);
  const cards = rides.map(rideCard).join('') || `<div class="empty">No matching rides yet. Save your route and app will show matches when drivers post.</div>`;
  return `<div class="card"><div class="h1">Find a safe seat</div><div class="grid"><label>Route shortcut<select id="presetSelect"><option value="">Choose route shortcut</option>${routePresetOptions()}</select></label><div class="grid2"><label>From<input id="fFrom" list="routeCities" value="${esc(state.filters.from)}" placeholder="Wah Cantt"></label><label>To<input id="fTo" list="routeCities" value="${esc(state.filters.to)}" placeholder="Islamabad"></label></div><label>Filter<select id="fRule"><option value="safe" ${state.filters.ride_rule==='safe'?'selected':''}>Only safe matching rides</option><option value="all" ${state.filters.ride_rule==='all'?'selected':''}>All rides</option><option value="female_only" ${state.filters.ride_rule==='female_only'?'selected':''}>Female-only seats</option><option value="male_only" ${state.filters.ride_rule==='male_only'?'selected':''}>Male-only seats</option><option value="family_only" ${state.filters.ride_rule==='family_only'?'selected':''}>Family only</option></select></label><div class="alert">Pickup point ab booking request me mention ho sakta hai, for example: New City, Barrier 3, Taxila stop.</div><button class="btn ghost" id="saveSearchRoute">Save this route & notify me</button></div>${routeDatalist()}</div>${cards}`;
}

function rideCard(r){
  const c = compatible(r); const existing = state.myBookings.find(b => b.ride_id === r.id && ['pending','accepted'].includes(b.status));
  return `<div class="card ride"><div class="row"><div><div class="route">${esc(r.from_city)} → ${esc(r.to_city)}</div><div class="small muted">${esc(r.pickup_area||'Pickup')} to ${esc(r.dropoff_area||'Dropoff')}</div></div><div class="fare">${money(r.price_per_seat)}</div></div><div class="meta"><span class="pill ok">${r.seats_left} seats left</span><span class="pill">${esc(ruleLabel(r.ride_rule))}</span><span class="pill ${c.ok?'ok':'bad'}">${esc(existing ? existing.status : c.msg)}</span></div><div class="small muted">${fmt(r.departure_at)} · ${esc(routeSummary(r))}</div><div class="small muted">${esc(r.driver_name)} · ${esc(r.driver_gender)} driver · ${esc(r.car_model||'Car')} ${esc(r.plate_number||'')}</div><div class="grid2"><button class="btn ghost" data-details="${r.id}">Details</button><button class="btn green" data-book="${r.id}" ${(!c.ok || existing)?'disabled':''}>${existing?'Requested':'Request seat'}</button></div></div>`;
}
function ruleLabel(x){ return ({mixed:'Mixed seats',male_only:'Male passengers only',female_only:'Female passengers only',family_only:'Family only'}[x] || x); }

function driverHome(){
  const rides = state.myRides.map(r => `<div class="card"><div class="row"><div><div class="route">${esc(r.from_city)} → ${esc(r.to_city)}</div><div class="small muted">${fmt(r.departure_at)} · ${esc(ruleLabel(r.ride_rule))} · ${esc(routeSummary(r))}</div></div><span class="pill ${r.status==='open'?'ok':'bad'}">${r.status}</span></div><div class="meta"><span class="pill ok">${r.seats_left} left / ${r.total_seats}</span><span class="pill">${money(r.price_per_seat)}</span></div><div class="grid2"><button class="btn ghost" data-details="${r.id}">Details</button><button class="btn danger" data-close-ride="${r.id}">Close ride</button></div></div>`).join('') || `<div class="empty">No rides posted yet.</div>`;
  return `<div class="card"><div class="h1">Driver dashboard</div><div class="grid2"><div class="kpi"><b>${state.myRides.length}</b><span class="muted small">Your rides</span></div><div class="kpi"><b>${state.requests.filter(b=>b.status==='pending').length}</b><span class="muted small">Pending requests</span></div></div></div>${rides}`;
}

function createRideView(){
  const vehicleOptions = state.vehicles.map(v=>`<option value="${v.id}">${esc(v.car_model)} · ${esc(v.plate_number)}</option>`).join('');
  return `<div class="card"><div class="h1">Post commute ride</div>${!state.vehicles.length?'<div class="alert">Add your car first in profile. Ride post needs a vehicle record.</div>':''}<form id="rideForm" class="grid"><label>Vehicle<select name="vehicle_id" required>${vehicleOptions}</select></label><label>Use popular route<select id="ridePresetSelect" name="route_code"><option value="">Custom route</option>${routePresetOptions()}</select></label><input name="route_name" type="hidden"><div class="grid2"><label>From city<input name="from_city" list="routeCities" required placeholder="Wah Cantt"></label><label>To city<input name="to_city" list="routeCities" required placeholder="Islamabad"></label></div><div class="grid2"><label>Pickup public point<input name="pickup_area" required placeholder="Wah Cantt Barrier 2"></label><label>Dropoff public point<input name="dropoff_area" required placeholder="Blue Area / Saddar"></label></div><div class="grid2"><label>Trip type<select name="trip_type"><option value="one_way">One way</option><option value="morning">Morning office/university</option><option value="evening">Evening return</option><option value="return">Two-way/return</option></select></label><label>Recurring<select name="recurrence_type"><option value="once">One time</option><option value="daily">Daily</option><option value="weekdays">Monday-Friday</option><option value="custom">Custom days</option></select></label></div><label>Days if custom<input name="recurrence_days" placeholder="Mon,Tue,Wed,Thu,Fri"></label><div class="grid2"><label>Departure date & time<input name="departure_at" type="datetime-local" required></label><label>Return time optional<input name="return_time" type="time"></label></div><div class="grid2"><label>Total seats<input name="total_seats" type="number" min="1" max="6" value="3" required></label><label>Price/seat per trip<input name="price_per_seat" type="number" min="0" value="500" required></label></div><div class="grid2"><label>Monthly seat allowed<select name="allow_monthly_booking"><option value="false">No</option><option value="true">Yes</option></select></label><label>Monthly price/seat<input name="monthly_price" type="number" min="0" placeholder="12000"></label></div><label>Passenger rule<select name="ride_rule"><option value="mixed">Mixed</option><option value="male_only">Male passengers only</option><option value="female_only">Female passengers only</option><option value="family_only">Family only</option></select></label><label>Notes<textarea name="notes" placeholder="Luggage, AC, exact gate, office/university group, payment terms, etc."></textarea></label>${routeDatalist()}<button class="btn green" ${!state.vehicles.length?'disabled':''}>Post ride</button></form></div>`;
}

function routesView(){
  const saved = state.savedRoutes.map(r=>`<div class="card"><div class="route">${esc(r.from_city)} → ${esc(r.to_city)}</div><div class="small muted">${esc(r.pickup_area||'Any pickup')} to ${esc(r.dropoff_area||'Any drop')} · ${esc(r.trip_type||'daily')} · ${esc(r.preferred_time||'any time')}</div><button class="btn danger" data-delete-route="${r.id}">Delete</button></div>`).join('') || '<div class="empty">No saved routes yet. Go to Search, enter From/To, then tap Save route.</div>';
  return `<div class="card"><div class="h1">Routes</div><p class="muted">Saved routes help you remember daily commute demand. Popular route cards are removed to keep this page clean.</p></div><div class="card"><div class="h2">Saved routes</div>${saved}</div><div class="card"><div class="h2">Notifications</div>${state.notifications.map(n=>`<div class="row"><div><b>${esc(n.title)}</b><div class="small muted">${esc(n.body)}</div></div><span class="small muted">${new Date(n.created_at).toLocaleDateString()}</span></div>`).join('') || '<p class="muted small">No notifications yet.</p>'}</div>`;
}

function bookingsView(){
  return state.myBookings.map(bookingCard).join('') || `<div class="empty">No bookings yet.</div>`;
}
function requestsView(){
  return state.requests.map(requestCard).join('') || `<div class="empty">No passenger requests yet.</div>`;
}
function bookingCard(b){
  return `<div class="card"><div class="row"><div><div class="route">${esc(b.from_city)} → ${esc(b.to_city)}</div><div class="small muted">${fmt(b.departure_at)} · Driver: ${esc(b.driver_name)}</div></div><span class="pill ${b.status==='accepted'?'ok':b.status==='pending'?'warn':'bad'}">${b.status}</span></div>${b.note?`<div class="alert" style="margin-top:12px"><b>Pickup request / note:</b><br>${esc(b.note)}</div>`:''}<div class="divider"></div><div class="grid2"><button class="btn ghost" data-contact="${b.id}" ${b.status!=='accepted'?'disabled':''}>Contact</button><button class="btn danger" data-cancel-booking="${b.id}" ${!['pending','accepted'].includes(b.status)?'disabled':''}>Cancel</button></div></div>`;
}
function requestCard(b){
  return `<div class="card"><div class="row"><div><div class="route">${esc(b.passenger_name)}</div><div class="small muted">${esc(b.passenger_gender)} · ${esc(b.travel_mode)} · ${esc(b.from_city)} → ${esc(b.to_city)}</div></div><span class="pill ${b.status==='accepted'?'ok':b.status==='pending'?'warn':'bad'}">${b.status}</span></div><div class="small muted">${fmt(b.departure_at)}</div>${b.note?`<div class="alert" style="margin-top:12px"><b>Passenger pickup request:</b><br>${esc(b.note)}</div>`:''}<div class="divider"></div><div class="grid2"><button class="btn green" data-accept="${b.id}" ${b.status!=='pending'?'disabled':''}>Accept</button><button class="btn danger" data-reject="${b.id}" ${b.status!=='pending'?'disabled':''}>Reject</button><button class="btn ghost" data-paid="${b.id}" ${b.status!=='accepted'?'disabled':''}>Mark paid</button></div></div>`;
}

function safetyView(){
  if (isAdmin()) return adminReports();
  return `<div class="card"><div class="h1">Safety center</div><div class="alert">Emergency me app ka wait na karein. Police/Rescue ko call karein. App report moderation ke liye hai.</div><div class="grid2" style="margin-top:12px"><a class="btn danger" href="tel:15">Call Police 15</a><a class="btn warn" href="tel:${esc(cfg.supportPhone)}">Call Support</a></div></div><div class="card"><div class="h2">Report issue</div><form id="reportForm" class="grid"><label>Type<select name="report_type"><option value="behavior">Bad behavior</option><option value="harassment">Harassment</option><option value="payment">Payment issue</option><option value="fake_profile">Fake profile</option><option value="other">Other</option></select></label><label>Details<textarea name="details" required></textarea></label><button class="btn">Submit report</button></form></div>`;
}

function profileView(){
  const p=state.profile, pp=state.privateProfile;
  const vehicles = state.vehicles.map(v=>`<div class="row"><span>${esc(v.car_model)} · ${esc(v.plate_number)}</span><span class="pill ${v.is_verified?'ok':'warn'}">${v.is_verified?'verified':'pending'}</span></div>`).join('') || '<p class="muted small">No vehicles added.</p>';
  return `<div class="card"><div class="h1">Profile</div><form id="profileForm" class="grid"><label>Full name<input name="full_name" value="${esc(p.full_name)}" required></label><div class="grid2"><label>Gender<select name="gender"><option value="male" ${p.gender==='male'?'selected':''}>Male</option><option value="female" ${p.gender==='female'?'selected':''}>Female</option></select></label><label>Travel mode<select name="travel_mode"><option value="solo" ${p.travel_mode==='solo'?'selected':''}>Solo</option><option value="family" ${p.travel_mode==='family'?'selected':''}>Family</option></select></label></div><label>Phone<input name="phone" value="${esc(pp?.phone||'')}" required></label><label>Emergency contact<input name="emergency_contact" value="${esc(pp?.emergency_contact||'')}"></label><button class="btn green">Save profile</button></form></div>${role()==='driver'?`<div class="card"><div class="h2">My vehicles</div>${vehicles}<div class="divider"></div><form id="vehicleForm" class="grid"><div class="grid2"><label>Car model<input name="car_model" required placeholder="Honda City"></label><label>Plate number<input name="plate_number" required placeholder="ICT-786"></label></div><label>Color<input name="color" placeholder="White"></label><button class="btn">Add vehicle</button></form></div>`:''}`;
}

function adminView(){
  if(state.tab==='adminUsers') return adminUsers();
  if(state.tab==='adminRides') return adminRides();
  if(state.tab==='safety') return adminReports();
  if(state.tab==='profile') return profileView();
  const a=state.admin||{};
  return `<div class="card"><div class="h1">Admin portal</div><div class="grid2"><div class="kpi"><b>${a.total_users||0}</b><span class="small muted">Users</span></div><div class="kpi"><b>${a.open_rides||0}</b><span class="small muted">Open rides</span></div><div class="kpi"><b>${a.pending_bookings||0}</b><span class="small muted">Pending bookings</span></div><div class="kpi"><b>${a.open_reports||0}</b><span class="small muted">Open reports</span></div></div></div>`;
}
function adminUsers(){ return `<div class="card"><div class="h1">Users</div><table class="table"><tr><th>Name</th><th>Role</th><th>Status</th><th>Action</th></tr>${state.users.map(u=>`<tr><td>${esc(u.full_name)}<br><span class="muted">${esc(u.gender)}</span></td><td>${esc(u.role)}</td><td>${esc(u.status)}</td><td><button class="btn ghost" data-user-status="${u.id}:${u.status==='active'?'suspended':'active'}">${u.status==='active'?'Suspend':'Activate'}</button></td></tr>`).join('')}</table></div>`; }
function adminRides(){ const vehicleRows = (state.vehicles||[]).map(v=>`<tr><td>${esc(v.car_model)}<br><span class="muted">${esc(v.plate_number)}</span></td><td>${esc(v.profiles?.full_name||'')}</td><td>${v.is_verified?'Verified':'Pending'}</td><td><button class="btn ghost" data-vehicle-verify="${v.id}:${v.is_verified?'false':'true'}">${v.is_verified?'Unverify':'Verify'}</button></td></tr>`).join(''); return `<div class="card"><div class="h1">Rides</div><table class="table"><tr><th>Route</th><th>Driver</th><th>Status</th></tr>${state.rides.concat(state.myRides).map(r=>`<tr><td>${esc(r.from_city)} → ${esc(r.to_city)}<br><span class="muted">${fmt(r.departure_at)}</span></td><td>${esc(r.driver_name)}</td><td>${esc(r.status)}<br>${r.seats_left}/${r.total_seats}<br><button class="btn ghost" data-close-ride="${r.id}">Close</button></td></tr>`).join('')}</table></div><div class="card"><div class="h1">Vehicle verification</div><table class="table"><tr><th>Vehicle</th><th>Owner</th><th>Status</th><th>Action</th></tr>${vehicleRows}</table></div>`; }
function adminReports(){ return `<div class="card"><div class="h1">Reports</div>${state.reports?.map(r=>`<div class="card" style="box-shadow:none"><div class="row"><b>${esc(r.report_type)}</b><span class="pill ${r.status==='open'?'warn':'ok'}">${esc(r.status)}</span></div><p class="small">${esc(r.details)}</p><p class="small muted">By ${esc(r.reporter_name)} · ${new Date(r.created_at).toLocaleString()}</p><button class="btn green" data-report-resolve="${r.id}" ${r.status!=='open'?'disabled':''}>Mark resolved</button></div>`).join('') || '<div class="empty">No reports</div>'}</div>`; }

function bindViewEvents(){
  const fFrom=$('#fFrom'), fTo=$('#fTo'), fRule=$('#fRule');
  if(fFrom) fFrom.oninput=e=>{state.filters.from=e.target.value; render();};
  if(fTo) fTo.oninput=e=>{state.filters.to=e.target.value; render();};
  if(fRule) fRule.onchange=e=>{state.filters.ride_rule=e.target.value; render();};
  const presetSelect=$('#presetSelect'); if(presetSelect) presetSelect.onchange=e=>applyPresetToSearch(e.target.value);
  const ridePresetSelect=$('#ridePresetSelect'); if(ridePresetSelect) ridePresetSelect.onchange=e=>applyPresetToRideForm(e.target.value);
  const saveSearchRoute=$('#saveSearchRoute'); if(saveSearchRoute) saveSearchRoute.onclick=saveCurrentRoute;
  document.querySelectorAll('[data-route-preset]').forEach(b=>b.onclick=()=>applyPresetToSearch(b.dataset.routePreset));
  document.querySelectorAll('[data-delete-route]').forEach(b=>b.onclick=()=>deleteSavedRoute(b.dataset.deleteRoute));
  document.querySelectorAll('[data-book]').forEach(b=>b.onclick=()=>openBookingModal(b.dataset.book));
  document.querySelectorAll('[data-details]').forEach(b=>b.onclick=()=>showRideDetails(b.dataset.details));
  document.querySelectorAll('[data-accept]').forEach(b=>b.onclick=()=>bookingAction('accept_booking_request',{p_booking_id:b.dataset.accept}));
  document.querySelectorAll('[data-reject]').forEach(b=>b.onclick=()=>bookingAction('reject_booking_request',{p_booking_id:b.dataset.reject,p_reason:'Rejected by driver'}));
  document.querySelectorAll('[data-cancel-booking]').forEach(b=>b.onclick=()=>bookingAction('cancel_booking_request',{p_booking_id:b.dataset.cancelBooking,p_reason:'Cancelled by passenger'}));
  document.querySelectorAll('[data-close-ride]').forEach(b=>b.onclick=()=>closeRide(b.dataset.closeRide));
  document.querySelectorAll('[data-contact]').forEach(b=>b.onclick=()=>getContact(b.dataset.contact));
  document.querySelectorAll('[data-report-resolve]').forEach(b=>b.onclick=()=>resolveReport(b.dataset.reportResolve));
  document.querySelectorAll('[data-user-status]').forEach(b=>b.onclick=()=>{const [id,status]=b.dataset.userStatus.split(':'); adminUserStatus(id,status);});
  document.querySelectorAll('[data-vehicle-verify]').forEach(b=>b.onclick=()=>{const [id,val]=b.dataset.vehicleVerify.split(':'); adminVehicleVerify(id,val==='true');});
  document.querySelectorAll('[data-paid]').forEach(b=>b.onclick=()=>bookingAction('mark_booking_paid',{p_booking_id:b.dataset.paid}));
  const rideForm=$('#rideForm'); if(rideForm) rideForm.onsubmit=createRide;
  const profileForm=$('#profileForm'); if(profileForm) profileForm.onsubmit=saveProfile;
  const vehicleForm=$('#vehicleForm'); if(vehicleForm) vehicleForm.onsubmit=addVehicle;
  const reportForm=$('#reportForm'); if(reportForm) reportForm.onsubmit=submitReport;
  const bookRideForm=$('#bookRideForm'); if(bookRideForm) bookRideForm.onsubmit=submitBookingRequest;
  const close=$('#modalClose'); if(close) close.onclick=()=>{state.modal=null; render();};
}


function applyPresetToSearch(code){
  const p=findPreset(code); if(!p) return;
  state.filters.from=p.from; state.filters.to=p.to; state.filters.ride_rule='safe'; render();
}
function applyPresetToRideForm(code){
  const p=findPreset(code); if(!p) return;
  const form=$('#rideForm'); if(!form) return;
  form.from_city.value=p.from; form.to_city.value=p.to; form.pickup_area.value=p.pickup; form.dropoff_area.value=p.dropoff;
  form.route_name.value=p.name; form.notes.value = `${p.via}\nEstimated ${p.distance}, ${p.time}.`;
}
async function saveCurrentRoute(){
  const from=(state.filters.from||'').trim(), to=(state.filters.to||'').trim();
  if(!from || !to) return toast('From and To required');
  const {error}=await supabase.from('saved_routes').insert({user_id:state.session.user.id, from_city:from, to_city:to, pickup_area:null, dropoff_area:null, trip_type:'daily', preferred_time:null, notify_enabled:true});
  if(error) toast(error.message); else {toast('Route saved'); await loadData();}
}
async function deleteSavedRoute(id){ const {error}=await supabase.from('saved_routes').delete().eq('id',id); if(error) toast(error.message); else {toast('Saved route deleted'); await loadData(); render();} }

async function createRide(e){
  e.preventDefault(); const f=Object.fromEntries(new FormData(e.target));
  if (new Date(f.departure_at) <= new Date()) return toast('Departure time must be in future');
  if (f.recurrence_type === 'custom' && !(f.recurrence_days || '').trim()) return toast('Please enter custom days');
  if (f.allow_monthly_booking === 'true' && !(+f.monthly_price > 0)) return toast('Please enter monthly seat price');
  const { error } = await supabase.rpc('create_ride', { p_vehicle_id:f.vehicle_id, p_from_city:f.from_city, p_to_city:f.to_city, p_pickup_area:f.pickup_area, p_dropoff_area:f.dropoff_area, p_departure_at:new Date(f.departure_at).toISOString(), p_total_seats:+f.total_seats, p_price_per_seat:+f.price_per_seat, p_ride_rule:f.ride_rule, p_notes:f.notes || null, p_route_code:f.route_code || null, p_route_name:f.route_name || null, p_trip_type:f.trip_type || 'one_way', p_recurrence_type:f.recurrence_type || 'once', p_recurrence_days:f.recurrence_days || null, p_return_time:f.return_time || null, p_allow_monthly_booking:f.allow_monthly_booking === 'true', p_monthly_price:f.monthly_price ? +f.monthly_price : null });
  if(error) toast(error.message); else { toast('Ride posted'); state.tab='home'; await loadData(); render(); }
}
function openBookingModal(ride_id){
  const r = state.rides.concat(state.myRides).find(x=>x.id===ride_id);
  if(!r) return;
  const c = compatible(r);
  const existing = state.myBookings.find(b => b.ride_id === r.id && ['pending','accepted'].includes(b.status));
  if (existing) return toast(`You already have a ${existing.status} request for this ride`);
  if (!c.ok) return toast(c.msg);
  state.modal = `<div class="modalBack"><div class="modal"><button class="btn ghost" id="modalClose">Close</button><div class="h1">Request seat</div><p class="muted">${esc(r.from_city)} → ${esc(r.to_city)} · ${fmt(r.departure_at)}</p><div class="card" style="box-shadow:none"><div class="row"><span>Driver pickup</span><b>${esc(r.pickup_area||'Not specified')}</b></div><div class="row"><span>Driver dropoff</span><b>${esc(r.dropoff_area||'Not specified')}</b></div><div class="row"><span>Fare / seat</span><b>${money(r.price_per_seat)}</b></div></div><form id="bookRideForm" class="grid"><input type="hidden" name="ride_id" value="${r.id}"><label>Your pickup point (optional)<input name="requested_pickup" placeholder="e.g. New City / Barrier 3 / Taxila stop"></label><label>Extra note for driver (optional)<textarea name="note" placeholder="Office gate, stop name, timing note, etc."></textarea></label><button class="btn green" ${!c.ok?'disabled':''}>${esc(c.msg==='Safe match'?'Send request':c.msg)}</button></form><p class="small muted">Example: if driver route is Barrier 3 → Blue Area, passenger can request pickup from New City here.</p></div></div>`;
  render();
}
async function submitBookingRequest(e){
  e.preventDefault();
  const f = Object.fromEntries(new FormData(e.target));
  const parts = [];
  if ((f.requested_pickup || '').trim()) parts.push(`Requested pickup: ${(f.requested_pickup || '').trim()}`);
  if ((f.note || '').trim()) parts.push((f.note || '').trim());
  const bookingNote = parts.join(' | ') || null;
  const { error } = await supabase.rpc('create_booking_request', { p_ride_id: f.ride_id, p_seats_requested: 1, p_note: bookingNote });
  if(error) toast(error.message); else { state.modal=null; toast('Booking request sent'); await loadData(); render(); }
}
async function bookingAction(fn,args){ const {error}=await supabase.rpc(fn,args); if(error) toast(error.message); else {toast('Updated'); await loadData(); render();} }
async function closeRide(id){ const {error}=await supabase.rpc('close_ride',{p_ride_id:id}); if(error) toast(error.message); else {toast('Ride closed'); await loadData(); render();} }
async function getContact(id){ const {data,error}=await supabase.rpc('get_booking_contact',{p_booking_id:id}); if(error) toast(error.message); else alert(`Contact: ${data?.full_name}\nPhone: ${data?.phone}\nEmergency: ${data?.emergency_contact||'Not added'}`); }
async function saveProfile(e){
  e.preventDefault(); const f=Object.fromEntries(new FormData(e.target));
  if (!(f.phone || '').trim()) return toast('Phone number is required');
  const [a,b]=await Promise.all([
    supabase.from('profiles').update({full_name:f.full_name, gender:f.gender, travel_mode:f.travel_mode}).eq('id',state.session.user.id),
    supabase.from('private_profiles').update({phone:f.phone, emergency_contact:f.emergency_contact || null}).eq('user_id',state.session.user.id)
  ]);
  if(a.error||b.error) toast(a.error?.message || b.error?.message); else {toast('Profile saved'); await loadMe(); render();}
}
async function addVehicle(e){ e.preventDefault(); const f=Object.fromEntries(new FormData(e.target)); const {error}=await supabase.from('vehicles').insert({owner_id:state.session.user.id, car_model:f.car_model, plate_number:f.plate_number, color:f.color || null}); if(error) toast(error.message); else {toast('Vehicle added. Admin can verify later.'); await loadData(); render();} }
async function submitReport(e){ e.preventDefault(); const f=Object.fromEntries(new FormData(e.target)); const {error}=await supabase.from('reports').insert({reporter_id:state.session.user.id, report_type:f.report_type, details:f.details}); if(error) toast(error.message); else {toast('Report submitted'); e.target.reset();} }
async function resolveReport(id){ const {error}=await supabase.from('reports').update({status:'resolved'}).eq('id',id); if(error) toast(error.message); else {toast('Report resolved'); await loadData(); render();} }
async function adminUserStatus(id,status){ const {error}=await supabase.rpc('admin_set_user_status',{p_user_id:id,p_status:status}); if(error) toast(error.message); else {toast('User updated'); await loadData(); render();} }
async function adminVehicleVerify(id,isVerified){ const {error}=await supabase.rpc('admin_set_vehicle_verified',{p_vehicle_id:id,p_verified:isVerified}); if(error) toast(error.message); else {toast('Vehicle updated'); await loadData(); render();} }
function showRideDetails(id){ const r=state.rides.concat(state.myRides).find(x=>x.id===id); if(!r) return; const c=compatible(r); const existing = state.myBookings.find(b => b.ride_id === r.id && ['pending','accepted'].includes(b.status)); state.modal=`<div class="modalBack"><div class="modal"><button class="btn ghost" id="modalClose">Close</button><div class="h1">${esc(r.from_city)} → ${esc(r.to_city)}</div><p class="muted">${fmt(r.departure_at)}</p><div class="card" style="box-shadow:none"><div class="row"><span>Fare</span><b>${money(r.price_per_seat)}</b></div><div class="row"><span>Seats left</span><b>${r.seats_left}/${r.total_seats}</b></div><div class="row"><span>Rule</span><b>${esc(ruleLabel(r.ride_rule))}</b></div><div class="row"><span>Commute</span><b>${esc(routeSummary(r)||'One time')}</b></div><div class="row"><span>Monthly</span><b>${r.allow_monthly_booking ? money(r.monthly_price || 0) : 'No'}</b></div><div class="row"><span>Driver</span><b>${esc(r.driver_name)} · ${esc(r.driver_gender)}</b></div><div class="row"><span>Car</span><b>${esc(r.car_model)} · ${esc(r.plate_number)}</b></div></div><div class="alert">Driver gender is shown clearly. Phone number appears only after booking is accepted.</div>${role()==='passenger'?`<button class="btn green" data-book="${r.id}" ${(!c.ok || existing)?'disabled':''}>${esc(existing ? `Already ${existing.status}` : (c.msg==='Safe match'?'Request seat':c.msg))}</button>`:''}</div></div>`; render(); }

if ('serviceWorker' in navigator) window.addEventListener('load', () => navigator.serviceWorker.register('/sw.js').catch(()=>{}));
