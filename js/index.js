// searchads-sdk — JS/React Native client for https://searchads.tools
// Write-only ingest: the applicationToken can ship inside your app. It cannot
// read any data back. Reading/managing data uses the secret sa_... api key
// against /api/agent/* — never from an app binary.

const DEFAULT_BASE = 'https://searchads.tools';

function createAnalytics(options) {
  if (!options || !options.applicationToken) {
    throw new Error('createAnalytics({ applicationToken }) is required');
  }
  const base = (options.baseUrl || DEFAULT_BASE).replace(/\/+$/, '');
  const state = {
    token: options.applicationToken,
    userId: options.userId || null,
    bundleId: options.bundleId || null,
    appVersion: options.appVersion || null,
    country: options.country || null,
  };

  async function post(path, body) {
    try {
      const res = await fetch(base + path, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      if (!res.ok) return false;
      const json = await res.json().catch(() => null);
      return !(json && json.status === 'error');
    } catch (e) {
      return false; // fire-and-forget: analytics must never crash the app
    }
  }

  function envelope(extra) {
    const body = { application_token: state.token, ...extra };
    if (state.bundleId && body.bundle_id === undefined) body.bundle_id = state.bundleId;
    if (state.appVersion && body.app_version === undefined) body.app_version = state.appVersion;
    if (state.country && body.country === undefined) body.country = state.country;
    return body;
  }

  return {
    /** Remember a stable user id used for every subsequent call. */
    setUserId(userId) { state.userId = userId; },

    /** Send an event. `props` is a flat object of strings/numbers/bools. */
    track(name, props) {
      const p = props || {};
      const userId = p.user_id || state.userId;
      const clean = { ...p }; delete clean.user_id;
      return post('/api/event', envelope({
        name,
        user_id: userId || undefined,
        props: Object.keys(clean).length ? clean : undefined,
      }));
    },

    /** Set user traits. Also stores props.user_id as the default user id. */
    identify(props) {
      const p = props || {};
      if (p.user_id) state.userId = p.user_id;
      return this.track('identify', p);
    },

    /** Record a purchase: { user_id?, amount, currency?, product_id? }. */
    trackPurchase(purchase) {
      const p = purchase || {};
      return post('/api/purchase_event', envelope({
        user_id: p.user_id || state.userId,
        amount: p.amount,
        currency: p.currency || 'USD',
        product_id: p.product_id,
      }));
    },

    /** Remap an anonymous id to a logged-in id (keeps attribution intact). */
    updateUserId(oldUserId, newUserId) {
      if (newUserId) state.userId = newUserId;
      return post('/api/attribution/update_user_id', envelope({
        old_user_id: oldUserId,
        new_user_id: newUserId,
      }));
    },
  };
}

module.exports = { createAnalytics };
