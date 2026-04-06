'use strict';

/* ──────────────────────────────────────
   State
   ────────────────────────────────────── */
let cfg = { min: 30, max: 360, default: 60 };
let selectedPlayer = null;
let nearbyPlayers  = [];
let prisoners      = [];
let hudTotal       = 0;   // total sentence in seconds (for progress bar)
let hudRemaining   = 0;

/* ──────────────────────────────────────
   Translation
   ────────────────────────────────────── */
let lang = {};

/** Retrieve a translated string; falls back to the key itself. */
function _(key) {
    return lang[key] !== undefined ? lang[key] : key;
}

/**
 * Walk all [data-i18n] and [data-i18n-placeholder] elements and apply
 * the current lang table.  Safe to call multiple times.
 */
function applyTranslations() {
    document.querySelectorAll('[data-i18n]').forEach(el => {
        const key = el.getAttribute('data-i18n');
        if (lang[key] !== undefined) el.textContent = lang[key];
    });
    document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
        const key = el.getAttribute('data-i18n-placeholder');
        if (lang[key] !== undefined) el.placeholder = lang[key];
    });
}

/* ──────────────────────────────────────
   NUI → Lua helper
   ────────────────────────────────────── */
function nuiPost(endpoint, data = {}) {
    return fetch(`https://esx_betterjail/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
    });
}

/* ──────────────────────────────────────
   Lua → NUI messages
   ────────────────────────────────────── */
window.addEventListener('message', ({ data }) => {
    switch (data.action) {
        case 'openUI':
            cfg           = data.config || cfg;
            nearbyPlayers = data.nearbyPlayers || [];
            prisoners     = data.prisoners     || [];
            if (data.lang) { lang = data.lang; applyTranslations(); }
            openPanel(data.tab || 'nearby');
            break;

        case 'updateNearby':
            nearbyPlayers = data.players || [];
            renderNearby();
            break;

        case 'updatePrisoners':
            prisoners = data.players || [];
            renderPrisoners();
            break;

        case 'showPrisonerHUD':
            hudTotal     = data.totalTime;   // seconds
            hudRemaining = data.time;        // seconds
            if (data.lang) { lang = data.lang; applyTranslations(); }
            showPrisonerHUD();
            break;

        case 'hidePrisonerHUD':
            hidePrisonerHUD();
            break;

        case 'updatePrisonerTime':
            hudRemaining = data.time;
            updateHUDTime();
            break;

        case 'updateZoneStatus':
            updateZoneStatus(data.inside);
            break;

        case 'openPrisonerMenu':
            if (data.lang) { lang = data.lang; applyTranslations(); }
            openPrisonerPanel(data.info);
            break;

        case 'prisonerNotification':
            showPrisonNotif(data.message);
            break;

        case 'foodRationUsed':
            startFoodCooldown(data.cooldownSecs);
            break;
    }
});

/* ──────────────────────────────────────
   Panel open / close
   ────────────────────────────────────── */
function openPanel(tab) {
    document.getElementById('jail-panel').classList.remove('hidden');
    switchTab(tab);
    renderNearby();
    renderPrisoners();
}

function closeUI() {
    document.getElementById('jail-panel').classList.add('hidden');
    resetForm();
    nuiPost('closeUI');
}

document.getElementById('close-btn').addEventListener('click', closeUI);
document.addEventListener('keydown', e => {
    if (e.key === 'Escape') {
        if (!document.getElementById('confirm-modal').classList.contains('hidden')) {
            closeModal();
        } else {
            closeUI();
        }
    }
});

/* ──────────────────────────────────────
   Tabs
   ────────────────────────────────────── */
document.querySelectorAll('.tab').forEach(btn => {
    btn.addEventListener('click', () => switchTab(btn.dataset.tab));
});

function switchTab(name) {
    document.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t.dataset.tab === name));
    document.querySelectorAll('.tab-content').forEach(c => c.classList.toggle('active', c.id === `tab-${name}`));
}

/* ──────────────────────────────────────
   Nearby Players
   ────────────────────────────────────── */
function renderNearby() {
    const list  = document.getElementById('nearby-list');
    const empty = document.getElementById('nearby-empty');
    const count = document.getElementById('nearby-count');

    count.textContent = nearbyPlayers.length;
    list.innerHTML    = '';
    resetForm();

    if (nearbyPlayers.length === 0) {
        list.classList.add('hidden');
        empty.classList.remove('hidden');
        return;
    }
    list.classList.remove('hidden');
    empty.classList.add('hidden');

    nearbyPlayers.forEach(p => {
        const card = document.createElement('div');
        card.className   = 'player-card';
        card.dataset.id  = p.serverId;
        const jailedTag  = p.jailTime > 0
            ? `<span class="player-jailed-tag">${_('tag_jailed')} · ${formatMinutes(p.jailTime)}</span>`
            : '';
        card.innerHTML = `
            <div class="player-avatar">${nameInitial(p.name)}</div>
            <div class="player-info">
                <div class="player-name">${escHtml(p.name)}</div>
                <div class="player-id"><span>${_('label_id')} ${p.serverId}</span>${jailedTag}</div>
            </div>
            <span class="player-arrow">›</span>`;
        card.addEventListener('click', () => selectPlayer(p, card));
        list.appendChild(card);
    });
}

function selectPlayer(player, cardEl) {
    document.querySelectorAll('.player-card').forEach(c => c.classList.remove('selected'));
    cardEl.classList.add('selected');
    selectedPlayer = player;
    showJailForm(player);
}

document.getElementById('refresh-nearby').addEventListener('click', function () {
    spinBtn(this);
    nuiPost('getNearbyPlayers').then(r => r.json()).then(players => {
        nearbyPlayers = players || [];
        renderNearby();
    });
});

/* ──────────────────────────────────────
   Jail Form
   ────────────────────────────────────── */
const slider    = document.getElementById('time-slider');
const timeInput = document.getElementById('time-input');
const timeHint  = document.getElementById('time-hint');

function showJailForm(player) {
    const form     = document.getElementById('jail-form');
    const isJailed = player.jailTime > 0;
    form.classList.remove('hidden');

    document.getElementById('form-avatar').textContent      = nameInitial(player.name);
    document.getElementById('form-player-name').textContent = player.name;
    document.getElementById('form-player-id').textContent   = `${_('label_id')} ${player.serverId}`;
    document.getElementById('jail-reason').value            = '';

    // Already-jailed notice
    const notice = document.getElementById('form-already-jailed');
    if (isJailed) {
        document.getElementById('form-existing-time').textContent = formatMinutes(player.jailTime);
        notice.classList.remove('hidden');
        document.getElementById('form-duration-label').textContent = _('label_add_time');
        document.getElementById('form-jail-label').textContent     = _('btn_add_time');
        document.getElementById('form-jail').classList.add('extend');
    } else {
        notice.classList.add('hidden');
        document.getElementById('form-duration-label').textContent = _('label_duration');
        document.getElementById('form-jail-label').textContent     = _('btn_jail');
        document.getElementById('form-jail').classList.remove('extend');
    }

    slider.min    = cfg.min;
    slider.max    = cfg.max;
    timeInput.min = cfg.min;
    timeInput.max = cfg.max;

    setTime(cfg.default);
}

function resetForm() {
    selectedPlayer = null;
    document.getElementById('jail-form').classList.add('hidden');
    document.querySelectorAll('.player-card').forEach(c => c.classList.remove('selected'));
}

function setTime(minutes) {
    const clamped = Math.min(cfg.max, Math.max(cfg.min, minutes));
    slider.value    = clamped;
    timeInput.value = clamped;
    updatePresetHighlight(clamped);
    updateTimeHint(clamped);
}

slider.addEventListener('input', () => setTime(parseInt(slider.value)));
timeInput.addEventListener('input', () => setTime(parseInt(timeInput.value) || cfg.min));

function updateTimeHint(minutes) {
    if (minutes < 60) {
        timeHint.textContent = `${minutes} ${_('time_unit')}`;
    } else {
        const h = Math.floor(minutes / 60);
        const m = minutes % 60;
        timeHint.textContent = m > 0 ? `${h}h ${m}m` : `${h}h`;
    }
}

function updatePresetHighlight(minutes) {
    document.querySelectorAll('.preset-btn').forEach(btn => {
        btn.classList.toggle('active', parseInt(btn.dataset.minutes) === minutes);
    });
}

document.querySelectorAll('.preset-btn').forEach(btn => {
    btn.addEventListener('click', () => setTime(parseInt(btn.dataset.minutes)));
});

document.getElementById('form-cancel').addEventListener('click', resetForm);

document.getElementById('form-jail').addEventListener('click', () => {
    if (!selectedPlayer) return;
    const time   = parseInt(timeInput.value);
    const reason = document.getElementById('jail-reason').value.trim();

    if (isNaN(time) || time < cfg.min || time > cfg.max) {
        shakeElement(timeInput);
        return;
    }
    const endpoint = selectedPlayer.jailTime > 0 ? 'addJailTime' : 'jailPlayer';
    nuiPost(endpoint, { serverId: selectedPlayer.serverId, time, reason });
    closeUI();
});

/* ──────────────────────────────────────
   Prisoners
   ────────────────────────────────────── */
function renderPrisoners(filter) {
    const list  = document.getElementById('prisoner-list');
    const empty = document.getElementById('prisoner-empty');
    const count = document.getElementById('prisoner-count');

    count.textContent = prisoners.length;
    list.innerHTML    = '';

    const query   = (filter || document.getElementById('prisoner-search').value || '').toLowerCase();
    const visible = query
        ? prisoners.filter(p => p.name.toLowerCase().includes(query))
        : prisoners;

    if (visible.length === 0) {
        list.classList.add('hidden');
        empty.classList.remove('hidden');
        return;
    }
    list.classList.remove('hidden');
    empty.classList.add('hidden');

    visible.forEach(p => {
        const card = document.createElement('div');
        card.className = 'prisoner-card';
        card.innerHTML = `
            <div class="player-avatar">${nameInitial(p.name)}</div>
            <div class="prisoner-info">
                <div class="prisoner-name">${escHtml(p.name)}</div>
                <div class="prisoner-meta">${_('label_id')} ${p.serverId}</div>
            </div>
            <div class="prisoner-time">
                <div class="prisoner-time-value">${formatMinutes(p.jailTime)}</div>
                <div class="prisoner-time-label">${_('label_remaining')}</div>
            </div>
            <button class="btn-release" data-id="${p.serverId}" data-name="${escHtml(p.name)}">
                ${_('btn_release')}
            </button>`;
        card.querySelector('.btn-release').addEventListener('click', () => {
            openConfirm(p);
        });
        list.appendChild(card);
    });
}

document.getElementById('prisoner-search').addEventListener('input', function () {
    renderPrisoners(this.value);
});

document.getElementById('refresh-prisoners').addEventListener('click', function () {
    spinBtn(this);
    nuiPost('getJailedPlayers').then(r => r.json()).then(players => {
        prisoners = players || [];
        renderPrisoners();
    });
});

/* ──────────────────────────────────────
   Release Confirm Modal
   ────────────────────────────────────── */
let pendingRelease = null;

function openConfirm(player) {
    pendingRelease = player;
    const tpl = _('release_confirm');
    // tpl may contain a %s placeholder (from Lua locale) or be a plain string
    document.getElementById('modal-body').textContent =
        tpl.includes('%s') ? tpl.replace('%s', player.name) : `${tpl} ${player.name}?`;

    document.getElementById('confirm-modal').classList.remove('hidden');
}

function closeModal() {
    pendingRelease = null;
    document.getElementById('confirm-modal').classList.add('hidden');
}

document.getElementById('modal-cancel').addEventListener('click', closeModal);
document.getElementById('modal-confirm').addEventListener('click', () => {
    if (!pendingRelease) return;
    nuiPost('releasePlayer', { serverId: pendingRelease.serverId });
    // Remove from local list immediately for snappy UX
    prisoners = prisoners.filter(p => p.serverId !== pendingRelease.serverId);
    renderPrisoners();
    closeModal();
});

/* ──────────────────────────────────────
   Prisoner HUD
   ────────────────────────────────────── */
function showPrisonerHUD() {
    document.getElementById('prisoner-hud').classList.remove('hidden');
    updateHUDTime();
}

function hidePrisonerHUD() {
    document.getElementById('prisoner-hud').classList.add('hidden');
}

function updateHUDTime() {
    const el  = document.getElementById('hud-time');
    const bar = document.getElementById('hud-progress-bar');

    el.textContent = formatSeconds(hudRemaining);

    const pct = hudTotal > 0 ? (hudRemaining / hudTotal) * 100 : 0;
    bar.style.width = `${Math.max(0, pct)}%`;

    // colour shift: green → yellow → red as time runs out
    if (pct > 60) {
        bar.style.background = 'linear-gradient(90deg, #d97706, #fbbf24)';
        el.style.color       = '#d97706';
    } else if (pct > 25) {
        bar.style.background = 'linear-gradient(90deg, #b45309, #f59e0b)';
        el.style.color       = '#f59e0b';
    } else {
        bar.style.background = 'linear-gradient(90deg, #991b1b, #dc2626)';
        el.style.color       = '#dc2626';
    }
}

function updateZoneStatus(inside) {
    const statusEl = document.getElementById('hud-zone-status');
    const textEl = document.getElementById('hud-zone-text');
    
    if (inside) {
        statusEl.classList.remove('outside');
        statusEl.classList.add('inside');
        textEl.textContent = _('zone_inside') || 'Inside Jail Zone';
    } else {
        statusEl.classList.remove('inside');
        statusEl.classList.add('outside');
        textEl.textContent = _('zone_outside') || 'Outside Jail Zone!';
    }
}

/* ──────────────────────────────────────
   Helpers
   ────────────────────────────────────── */
function nameInitial(name) {
    return (name || '?').charAt(0).toUpperCase();
}

function escHtml(str) {
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

function formatSeconds(secs) {
    if (secs <= 0) return '00:00';
    const h = Math.floor(secs / 3600);
    const m = Math.floor((secs % 3600) / 60);
    const s = secs % 60;
    if (h > 0) return `${pad(h)}:${pad(m)}:${pad(s)}`;
    return `${pad(m)}:${pad(s)}`;
}

function formatMinutes(mins) {
    if (!mins || mins <= 0) return '0m';
    if (mins < 60) return `${mins}m`;
    const h = Math.floor(mins / 60);
    const m = mins % 60;
    return m > 0 ? `${h}h ${m}m` : `${h}h`;
}

function pad(n) { return String(n).padStart(2, '0'); }

function shakeElement(el) {
    el.style.animation = 'none';
    el.getBoundingClientRect(); // force reflow
    el.style.animation = 'shake 0.3s ease-out';
}

function spinBtn(btn) {
    btn.classList.add('spinning');
    setTimeout(() => btn.classList.remove('spinning'), 700);
}

/* ──────────────────────────────────────
   Jail Log Tab
   ────────────────────────────────────── */
let logEntries    = [];
let logFilter     = 'all';

function loadLog() {
    nuiPost('getJailLog').then(r => r.json()).then(entries => {
        logEntries = entries || [];
        renderLog();
    });
}

function renderLog() {
    const list   = document.getElementById('log-list');
    const empty  = document.getElementById('log-empty');
    const search = (document.getElementById('log-search').value || '').toLowerCase();

    list.innerHTML = '';

    let visible = logEntries;
    if (logFilter !== 'all') visible = visible.filter(e => e.action === logFilter);
    if (search)              visible = visible.filter(e =>
        (e.prisoner_name || '').toLowerCase().includes(search) ||
        (e.officer_name  || '').toLowerCase().includes(search)
    );

    if (visible.length === 0) {
        list.classList.add('hidden');
        empty.classList.remove('hidden');
        return;
    }
    list.classList.remove('hidden');
    empty.classList.add('hidden');

    visible.forEach(entry => {
        const el = document.createElement('div');
        el.className = 'log-entry';

        const badge  = logBadge(entry.action);
        const names  = logNames(entry);
        const meta   = logMeta(entry);
        const ts     = relativeTime(entry.created_at);

        el.innerHTML = `
            <span class="log-badge ${entry.action}">${badge}</span>
            <div class="log-body">
                <div class="log-names">${names}</div>
                ${meta ? `<div class="log-meta">${meta}</div>` : ''}
            </div>
            <div class="log-time">${ts}</div>`;
        list.appendChild(el);
    });
}

function logBadge(action) {
    const map = {
        jailed:   _('filter_jailed'),
        released: _('filter_released'),
        bail:     _('filter_bail'),
        expired:  _('filter_expired'),
        extended: _('filter_extended'),
    };
    return (map[action] || action).toUpperCase();
}

function logNames(entry) {
    const prisoner = escHtml(entry.prisoner_name || '?');
    if (entry.action === 'jailed') {
        return `${escHtml(entry.officer_name || '?')} <span class="log-arrow">→</span> ${prisoner}`;
    } else if (entry.action === 'released') {
        return `${escHtml(entry.officer_name || '?')} <span class="log-arrow">↩</span> ${prisoner}`;
    }
    return prisoner;
}

function logMeta(entry) {
    const parts = [];
    if (entry.duration && entry.duration > 0) parts.push(formatMinutes(entry.duration));
    if (entry.reason) parts.push(escHtml(entry.reason));
    return parts.join(' · ');
}

function relativeTime(ts) {
    if (!ts) return '';
    // MySQL returns "YYYY-MM-DD HH:MM:SS" — replace space with T for parsing
    const d    = new Date(String(ts).replace(' ', 'T') + 'Z');
    const diff = Math.floor((Date.now() - d.getTime()) / 1000);
    if (isNaN(diff) || diff < 0)  return _('time_just_now');
    if (diff < 60) {
        const tpl = _('time_seconds_ago');
        return tpl.includes('%d') ? tpl.replace('%d', diff) : `${diff}s ago`;
    }
    if (diff < 3600) {
        const tpl = _('time_minutes_ago');
        return tpl.includes('%d') ? tpl.replace('%d', Math.floor(diff/60)) : `${Math.floor(diff/60)}m ago`;
    }
    if (diff < 86400) {
        const tpl = _('time_hours_ago');
        return tpl.includes('%d') ? tpl.replace('%d', Math.floor(diff/3600)) : `${Math.floor(diff/3600)}h ago`;
    }
    const tpl = _('time_days_ago');
    return tpl.includes('%d') ? tpl.replace('%d', Math.floor(diff/86400)) : `${Math.floor(diff/86400)}d ago`;
}

// Filter buttons
document.getElementById('log-filters').addEventListener('click', e => {
    const btn = e.target.closest('.log-filter');
    if (!btn) return;
    logFilter = btn.dataset.filter;
    document.querySelectorAll('.log-filter').forEach(b => b.classList.toggle('active', b === btn));
    renderLog();
});

document.getElementById('log-search').addEventListener('input', renderLog);

document.getElementById('refresh-log').addEventListener('click', function () {
    spinBtn(this);
    loadLog();
});

// Auto-load when switching to the log tab
let logLoaded = false;
document.querySelectorAll('.tab').forEach(btn => {
    btn.addEventListener('click', () => {
        if (btn.dataset.tab === 'log' && !logLoaded) {
            logLoaded = true;
            loadLog();
        }
    });
});

/* ──────────────────────────────────────
   Prisoner Services Panel
   ────────────────────────────────────── */
let prisonerInfo       = null;
let foodCooldownTimer  = null;
let foodCooldownRemain = 0;

function openPrisonerPanel(info) {
    prisonerInfo = info;
    const panel = document.getElementById('prisoner-panel');
    panel.classList.remove('hidden');

    // Sentence display
    const timeEl = document.getElementById('ps-time');
    const barEl  = document.getElementById('ps-bar');
    const subEl  = document.getElementById('ps-sub');
    timeEl.textContent = formatMinutes(info.jailTime);
    const remaining = _('sentence_remaining');
    subEl.textContent  = remaining.includes('%s')
        ? remaining.replace('%s', formatMinutes(info.jailTime))
        : `${formatMinutes(info.jailTime)} ${_('label_remaining')}`;
    barEl.style.width  = '100%';

    // Bail section - WICHTIG: Immer neu berechnen
    const bailCard    = document.getElementById('bail-card');
    const bailCostEl  = document.getElementById('bail-cost');
    const balanceEl   = document.getElementById('bail-balance');
    const bailBtn     = document.getElementById('btn-pay-bail');

    if (!info.bailEnabled || info.jailTime <= 0) {
        bailCard.style.display = 'none';
    } else {
        bailCard.style.display = '';
        
        // Aktualisiere IMMER die Werte
        bailCostEl.textContent = formatMoney(info.bailCost);
        balanceEl.textContent  = formatMoney(info.money);
        
        // Button Status neu berechnen
        bailBtn.disabled = info.money < info.bailCost;
        
        if (bailBtn.disabled) {
            const tpl = _('bail_need_more');
            const needed = info.bailCost - info.money;
            bailBtn.textContent = tpl.includes('%s')
                ? tpl.replace('%s', formatMoney(needed))
                : `${tpl}: ${formatMoney(needed)}`;
        } else {
            bailBtn.textContent = _('btn_pay_bail');
        }
    }

    // Food section
    const foodCard = document.getElementById('food-card');
    if (!info.foodEnabled) {
        foodCard.style.display = 'none';
    } else {
        foodCard.style.display = '';
        if (info.foodAvailable) {
            setFoodAvailable();
        } else {
            startFoodCooldown(info.foodCooldownSecs);
        }
    }

    hidePrisonNotif();
}

function closePrisonerPanel() {
    document.getElementById('prisoner-panel').classList.add('hidden');
    if (foodCooldownTimer) { clearInterval(foodCooldownTimer); foodCooldownTimer = null; }
    nuiPost('closePrisonerUI');
}

document.getElementById('prisoner-close-btn').addEventListener('click', closePrisonerPanel);

// ESC also closes prisoner panel
document.addEventListener('keydown', e => {
    if (e.key === 'Escape') {
        if (!document.getElementById('prisoner-panel').classList.contains('hidden')) {
            closePrisonerPanel();
        }
    }
});

// Pay bail
document.getElementById('btn-pay-bail').addEventListener('click', () => {
    const bailBtn = document.getElementById('btn-pay-bail');
    if (bailBtn.disabled) return;
    
    bailBtn.disabled = true;
    nuiPost('payBail');
    closePrisonerPanel();
});

// Collect food ration
document.getElementById('btn-food').addEventListener('click', () => {
    if (document.getElementById('btn-food').disabled) return;
    document.getElementById('btn-food').disabled = true;
    nuiPost('collectFoodRation');
});

function setFoodAvailable() {
    const statusEl = document.getElementById('food-status');
    const btnEl    = document.getElementById('btn-food');
    statusEl.textContent = _('food_available');
    statusEl.className   = 'food-status';
    btnEl.disabled       = false;
    btnEl.textContent    = _('btn_food');
    if (foodCooldownTimer) { clearInterval(foodCooldownTimer); foodCooldownTimer = null; }
}

function startFoodCooldown(secs) {
    foodCooldownRemain = secs;
    const statusEl = document.getElementById('food-status');
    const btnEl    = document.getElementById('btn-food');
    btnEl.disabled = true;

    function tick() {
        if (foodCooldownRemain <= 0) {
            setFoodAvailable();
            return;
        }
        statusEl.textContent = `${_('food_next_in')} ${formatSeconds(foodCooldownRemain)}`;
        statusEl.className   = 'food-status cooldown';
        btnEl.textContent    = _('food_on_cooldown');
        foodCooldownRemain--;
    }
    tick();
    if (foodCooldownTimer) clearInterval(foodCooldownTimer);
    foodCooldownTimer = setInterval(tick, 1000);
}

function showPrisonNotif(msg) {
    const el = document.getElementById('prison-notif');
    el.textContent = msg;
    el.classList.remove('hidden');
    setTimeout(() => el.classList.add('hidden'), 4000);
}

function hidePrisonNotif() {
    document.getElementById('prison-notif').classList.add('hidden');
}

function formatMoney(amount) {
    return '$' + Number(amount).toLocaleString();
}

/* Shake keyframe injected via JS to keep CSS clean */
const style = document.createElement('style');
style.textContent = `@keyframes shake {
    0%,100%{transform:translateX(0)}
    20%{transform:translateX(-5px)}
    60%{transform:translateX(5px)}
    80%{transform:translateX(-3px)}
}`;
document.head.appendChild(style);
