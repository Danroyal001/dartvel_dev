/// The screen Studio shows until its first owner has finished setting up.
///
/// Plain HTML, served by the mount itself: it has to render before Studio's
/// own application is trusted to load, on any target, with no build step.
/// Until the owner has set their own password and turned on a second factor,
/// this is what every route on the mount answers with.
library dartvel_core.admin.first_run_screen;

/// The page, with [mount] as the address its form posts to.
String dvFirstRunScreen({required String mount, required String address}) => '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Finish setting up</title>
<style>
  :root { color-scheme: light dark; --ink: #16161d; --muted: #6b6b7b;
    --line: #e4e4eb; --card: #ffffff; --page: #f3f3f7; --accent: #6c4bf4; }
  @media (prefers-color-scheme: dark) {
    :root { --ink: #f0f0f5; --muted: #a6a6b4; --line: #2b2b35;
      --card: #1b1b22; --page: #111116; }
  }
  body { margin: 0; background: var(--page); color: var(--ink);
    font: 15px/1.5 ui-sans-serif, system-ui, -apple-system, sans-serif; }
  main { max-width: 420px; margin: 0 auto; padding: 48px 16px; }
  .card { background: var(--card); border: 1px solid var(--line);
    border-radius: 12px; padding: 24px; }
  h1 { font-size: 22px; margin: 0 0 8px; }
  p { color: var(--muted); margin: 0 0 16px; }
  label { display: block; font-size: 13px; margin: 14px 0 6px; }
  input { width: 100%; box-sizing: border-box; padding: 10px 12px;
    border: 1px solid var(--line); border-radius: 8px; background: var(--page);
    color: var(--ink); font-size: 15px; }
  button { width: 100%; margin-top: 18px; padding: 11px 14px; border: 0;
    border-radius: 8px; background: var(--accent); color: #fff;
    font-size: 15px; font-weight: 600; cursor: pointer; }
  .note { font-size: 13px; color: var(--muted); margin-top: 14px; }
  .secret { font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    background: var(--page); border: 1px solid var(--line); border-radius: 8px;
    padding: 10px 12px; word-break: break-all; font-size: 13px; }
  .bad { color: #d1344b; font-size: 13px; margin-top: 12px; }
  .step { display: none; }
  .step[data-on] { display: block; }
</style>
</head>
<body>
<main>
  <div class="card">
    <h1>Finish setting up</h1>
    <p>This application printed a password when it first ran. Studio opens
      once you have replaced it and turned on a second factor.</p>

    <form class="step" data-on id="one">
      <label for="password">The password it printed</label>
      <input id="password" type="password" autocomplete="current-password" required>
      <label for="next">Your new password</label>
      <input id="next" type="password" autocomplete="new-password" required>
      <button type="submit">Change it</button>
      <p class="note">Signing in as $address.</p>
      <p class="bad" id="one-bad"></p>
    </form>

    <form class="step" id="two">
      <p>Scan this in an authenticator app, or type the key into it.</p>
      <div class="secret" id="secret"></div>
      <label for="code">The six digits it shows</label>
      <input id="code" inputmode="numeric" autocomplete="one-time-code" required>
      <button type="submit">Turn it on</button>
      <p class="bad" id="two-bad"></p>
    </form>
  </div>
</main>
<script>
  const mount = ${_json(mount)};
  const address = ${_json(address)};
  const csrf = 'b'.repeat(32);
  const post = (path, body) => fetch(path, {
    method: 'POST', credentials: 'same-origin',
    headers: { 'content-type': 'application/json',
      'x-dartvel-csrf-token': csrf },
    body: JSON.stringify(body),
  });
  const show = (id) => {
    for (const step of document.querySelectorAll('.step')) {
      step.toggleAttribute('data-on', step.id === id);
    }
  };
  document.getElementById('one').addEventListener('submit', async (e) => {
    e.preventDefault();
    const bad = document.getElementById('one-bad');
    bad.textContent = '';
    const current = document.getElementById('password').value;
    const next = document.getElementById('next').value;
    const signedIn = await post('/api/auth/sign-in',
      { email: address, password: current });
    if (!signedIn.ok) {
      bad.textContent = 'That is not the password this application printed.';
      return;
    }
    const changed = await post(mount + '/api/first-run/password',
      { current: current, password: next });
    if (!changed.ok) {
      bad.textContent = (await changed.json()).message || 'That did not work.';
      return;
    }
    const started = await post(mount + '/api/first-run/second-factor', {});
    const enrolment = await started.json();
    document.getElementById('secret').textContent = enrolment.secret || '';
    show('two');
  });
  document.getElementById('two').addEventListener('submit', async (e) => {
    e.preventDefault();
    const bad = document.getElementById('two-bad');
    bad.textContent = '';
    const done = await post(mount + '/api/first-run/second-factor/confirm',
      { code: document.getElementById('code').value });
    if (!done.ok) {
      bad.textContent = 'That code did not match. Try the next one.';
      return;
    }
    location.href = mount + '/';
  });
</script>
</body>
</html>
''';

String _json(String value) =>
    "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";
