# Supabase setup

OrcaBox uses Supabase for auth, sync (My List / history / backups), Watch
Together realtime, avatar storage, and TV pairing. Everything except **TV
pairing** is plain PostgREST + row-level security and needs no server code.

There is exactly **one** edge function: [`functions/pair-tv`](functions/pair-tv/index.ts).

## Do I need the edge function?

| Feature | Needs `pair-tv`? |
|---|---|
| Email/password sign-in, sign-up, password reset | No |
| My List, watch history, reading history, cloud backup | No |
| Watch Together (rooms, chat, presence) | No |
| Avatars | No |
| **Sign in on the TV by scanning a QR with your phone** | **Yes** |
| **Connecting AniList/MAL on a TV via the browser login page** | **Yes** |

Without it the app still runs; `TvPairingService` just fails every poll, so the
TV pairing screen never leaves "waiting for approval". If you are not shipping
the TV flow yet, you can skip this entirely and come back to it.

The planned web interface will talk to the same Supabase project — the REST and
realtime APIs need nothing deployed, so this function is only on the critical
path for the TV flows above.

## Prerequisites

The function reads and writes `public.tv_pairings`, created in
[`migrations/0001_schema.sql`](migrations/0001_schema.sql) with its RLS policy in
[`0002_rls.sql`](migrations/0002_rls.sql). Check the table exists before
deploying — in the dashboard, Table Editor, or:

```sql
select count(*) from public.tv_pairings;
```

> [!IMPORTANT]
> These migrations were applied **by hand** in the SQL editor, not through the
> CLI, so this project has no `supabase_migrations` history. Do **not** run
> `supabase db push` — it would try to replay every file, and the `create
> policy` statements in `0002_rls.sql` fail when the policies already exist.
> Apply new SQL by pasting it into the SQL editor, the same way `0001`–`0004`
> were. (Also note `0003_realtime.sql` and `0003_storage.sql` share a version
> number, which the CLI's migration ordering cannot represent — another reason
> to keep applying these by hand until they are renumbered.)

## Deploying `pair-tv`

```bash
npm install -g supabase
```

```bash
supabase login
```

Link this folder to your project. The ref is the subdomain of `SUPABASE_URL` —
for `https://dcqvdakittdsvgwslnqu.supabase.co` the ref is `dcqvdakittdsvgwslnqu`:

```bash
supabase link --project-ref <your-project-ref>
```

Set the function's secrets. Copy `.env.example` to `supabase/.env` (gitignored),
fill it in, then:

```bash
supabase secrets set --env-file supabase/.env
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected by the platform —
do not set those yourself, and never put the service-role key in the app's
`.env`.

Deploy:

```bash
supabase functions deploy pair-tv
```

`config.toml` already sets `verify_jwt = false` for this function, and the
reasoning is documented there — the callers are a signed-out TV and an
anonymous browser page, and the function authorizes each action itself.

Verify it answers (a bad action should come back as JSON, not a gateway error):

```bash
curl -s -X POST "https://<your-project-ref>.supabase.co/functions/v1/pair-tv" -H "content-type: application/json" -d '{"action":"ping"}'
```

Expect `{"ok":false,"error":"bad_action"}`. Then test end to end: open the TV
pairing screen, scan with the signed-in phone, approve.

## Missing piece: the `/tv-connect` page

`TvTrackerConnectScreen` shows a QR pointing at `${SITE_BASE_URL}/tv-connect/`
(see `lib/features/auth/tv_tracker_connect_screen.dart`), but the site has no
such route — only `/`, `/guide`, `/open` and `/pair` exist. So after deploying
this function:

- **Phone-app pairing works** — the TV QR opens `/pair` or the app, the
  signed-in phone calls `approve`, the TV polls and signs in.
- **Browser tracker login does not** — the QR lands on a 404. That page is what
  calls the function's `exchange` and `drop` actions, so those two branches
  stay unused until it is built.

Build `/tv-connect` when you build the web interface, or hide the
tracker-connect entry point on TV until then.

## Also set in the dashboard

- **Authentication → URL Configuration**: set Site URL to `SITE_BASE_URL`
  (`https://orcabox.vercel.app`) and add it to the redirect allow-list. The
  password-reset email lands on that page, so a stale value breaks reset.
- **Authentication → SMTP**: the sender address the reset emails come from.

## Tracker OAuth redirect URIs

The TV browser-login page does an `authorization_code` exchange through this
function, so each tracker app needs the **web** redirect registered alongside
the app's `orcabox://` deep link:

| Tracker | App redirect | Web redirect (TV login) |
|---|---|---|
| AniList | `orcabox://anilist-auth` | `https://orcabox.vercel.app/tv-connect/` |
| MyAnimeList | `orcabox://mal-auth` | `https://orcabox.vercel.app/tv-connect/` |

## Dead code in the function

The `simkl` branch of the `exchange` action is unreachable from the current
app — `lib/core/tracker/simkl_service.dart` was removed under NOTES task 15.
Its client id and secret are read from the environment and default to empty, so
the branch simply fails if anything ever calls it. Delete the branch (and the
`SIMKL_*` keys in `.env.example`) once you are sure no older build is still in
the wild.
