/// Studio's own sign-in, at `<mount>/login`.
///
/// Studio signs people in at its own mount, as wp-admin does, rather than
/// sending them to the application's `/login`. An application can turn its
/// account pages off, move them, or replace them with its own, and Studio
/// still has to open; the application's router does not even know the mount
/// is there, so the page it would come back to after signing in was the
/// application's own not-found page.
///
/// Plain HTML, served by the mount itself, like the first-run screen: it has
/// to render before Studio's application is trusted to load. It drives the
/// application's own auth endpoints -- sign in, then the second factor when
/// the account has one -- so the rate limit, the CSRF check and the session
/// rotation stay in one place. Whether the person may open Studio is still
/// decided by the mount, on the Studio.access grant, when the page sends
/// them there.
library dartvel_core.admin.studio_sign_in_screen;

/// The page, for [mount], signing in through the auth endpoints under [api].
String dvStudioSignInScreen({required String mount, required String api}) => '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Sign in to Studio</title>
<style>
  :root { color-scheme: light dark; --ink: #16161d; --muted: #6b6b7b;
    --line: #e4e4eb; --card: #ffffff; --page: #f3f3f7; --accent: #6c4bf4; }
  @media (prefers-color-scheme: dark) {
    :root { --ink: #f0f0f5; --muted: #a6a6b4; --line: #2b2b35;
      --card: #1b1b22; --page: #111116; }
  }
  body { margin: 0; background: var(--page); color: var(--ink);
    font: 15px/1.5 ui-sans-serif, system-ui, -apple-system, sans-serif; }
  main { max-width: 400px; margin: 0 auto; padding: 72px 16px 48px; }
  .card { background: var(--card); border: 1px solid var(--line);
    border-radius: 12px; padding: 24px; }
  h1 { font-size: 22px; margin: 0 0 6px; }
  p { color: var(--muted); margin: 0 0 12px; }
  label { display: block; font-size: 13px; margin: 14px 0 6px; }
  input { width: 100%; box-sizing: border-box; padding: 10px 12px;
    border: 1px solid var(--line); border-radius: 8px; background: var(--page);
    color: var(--ink); font-size: 15px; }
  button { width: 100%; margin-top: 18px; padding: 11px 14px; border: 0;
    border-radius: 8px; background: var(--accent); color: #fff;
    font-size: 15px; font-weight: 600; cursor: pointer; }
  button[disabled] { opacity: .6; cursor: default; }
  .bad { color: #d1344b; font-size: 13px; margin: 12px 0 0; min-height: 1em; }
  .step { display: none; }
  .step[data-on] { display: block; }
</style>
</head>
<body>
<main>
  <div class="card">
    <h1>Sign in to Studio</h1>
    <form class="step" data-on id="password-step">
      <label for="email">Email</label>
      <input id="email" type="email" autocomplete="username" required autofocus>
      <label for="password">Password</label>
      <input id="password" type="password" autocomplete="current-password" required>
      <button type="submit">Sign in</button>
      <p class="bad" id="password-bad" role="alert"></p>
    </form>
    <form class="step" id="code-step">
      <p>Enter the code from your authenticator app, or a recovery code.</p>
      <label for="code">Code</label>
      <input id="code" autocomplete="one-time-code" required>
      <button type="submit">Continue</button>
      <p class="bad" id="code-bad" role="alert"></p>
    </form>
  </div>
</main>
<script>
  const mount = ${_json(mount)};
  const api = ${_json(api)};
  const csrf = Array.from(crypto.getRandomValues(new Uint8Array(16)),
    (b) => b.toString(16).padStart(2, '0')).join('');
  // Only somewhere inside Studio: a from that leaves the mount, or names
  // this page, goes to Studio's front page instead.
  const target = (() => {
    const from = new URLSearchParams(location.search).get('from') || '';
    const inside = from === mount || from.startsWith(mount + '/');
    const login = from === mount + '/login' || from.startsWith(mount + '/login?');
    return inside && !login && !from.includes('//') ? from : mount + '/';
  })();
  const post = (path, body) => fetch(api + path, {
    method: 'POST', credentials: 'same-origin',
    headers: { 'content-type': 'application/json',
      'x-dartvel-csrf-token': csrf },
    body: JSON.stringify(body),
  });
  const show = (id) => {
    for (const step of document.querySelectorAll('.step')) {
      step.toggleAttribute('data-on', step.id === id);
    }
    const first = document.querySelector('#' + id + ' input');
    if (first) first.focus();
  };
  // Signed in: Studio itself decides whether this person may open it.
  const open = async (bad) => {
    const probe = await fetch(mount + '/', { credentials: 'same-origin',
      redirect: 'manual' });
    if (probe.type === 'opaqueredirect' || !probe.ok) {
      bad.textContent = 'This account may not open Studio.';
      return;
    }
    location.replace(target);
  };
  const busy = (form, on) => {
    form.querySelector('button').toggleAttribute('disabled', on);
  };
  document.getElementById('password-step').addEventListener('submit', async (e) => {
    e.preventDefault();
    const form = e.currentTarget;
    const bad = document.getElementById('password-bad');
    bad.textContent = '';
    busy(form, true);
    try {
      const res = await post('/auth/sign-in', {
        email: document.getElementById('email').value,
        password: document.getElementById('password').value,
      });
      if (res.status === 429) {
        bad.textContent = 'Too many attempts. Wait a minute and try again.';
        return;
      }
      if (!res.ok) {
        bad.textContent = 'That email and password do not match an account.';
        return;
      }
      const body = await res.json().catch(() => ({}));
      if (body.mfaRequired) { show('code-step'); return; }
      await open(bad);
    } catch (_) {
      bad.textContent = 'Could not reach the server. Try again.';
    } finally {
      busy(form, false);
    }
  });
  document.getElementById('code-step').addEventListener('submit', async (e) => {
    e.preventDefault();
    const form = e.currentTarget;
    const bad = document.getElementById('code-bad');
    bad.textContent = '';
    busy(form, true);
    try {
      const value = document.getElementById('code').value.trim();
      const res = await post('/auth/second-factor', /^[0-9 ]+\$/.test(value)
        ? { code: value.replace(/ /g, '') } : { recoveryCode: value });
      if (!res.ok) {
        bad.textContent = 'That code did not match. Try the next one.';
        return;
      }
      await open(bad);
    } catch (_) {
      bad.textContent = 'Could not reach the server. Try again.';
    } finally {
      busy(form, false);
    }
  });
</script>
</body>
</html>
''';

String _json(String value) =>
    "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll('<', r'\x3c')}'";
