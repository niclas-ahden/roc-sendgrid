# roc-sendgrid

Send emails via the [SendGrid v3 API](https://docs.sendgrid.com/api-reference/mail-send/mail-send) from Roc.

## Example usage

```roc
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.27.0/HZanbveSUDoJF8LypR663eH7PpaKEKG36eErEQzmV1Qs.tar.zst",
	sendgrid: "https://github.com/niclas-ahden/roc-sendgrid/releases/download/0.2.0/GFp74ugf9Z6f9GdeQFzoSRXXKdJpevmqR3AdjuRKwK3F.tar.zst",
}

import pf.Env
import pf.Http
import pf.OsStr
import pf.Stdout
import sendgrid.SendGrid

main! = |_args|
	match env_var!("SENDGRID_API_KEY") {
		Err(_) => Stdout.line!("SENDGRID_API_KEY is not set, so nothing was sent.")
		Ok(api_key) => {
			client = SendGrid.init({ http_send!: Http.send!, api_key })

			response = SendGrid.send_email!(
				client,
				{
					from: { email: env_var!("SENDGRID_FROM")? },
					to: [{ email: env_var!("SENDGRID_TO")? }],
					subject: "Hello from Roc!",
					content: [{ mime_type: "text/plain", value: "Sent via roc-sendgrid." }],
				},
			)?

			Stdout.line!("SendGrid accepted the email as ${response.message_id}")
		}
	}

env_var! = |name| Env.var_str!(OsStr.from_str(name))
```

SendGrid only sends from a [verified sender](https://www.twilio.com/docs/sendgrid/ui/sending-email/sender-verification). When it refuses an email, the error says why:

```
SendGridRejected({
	body: "{\"errors\":[{\"message\":\"The from address does not match a verified Sender Identity. ...\"}]}",
	headers: [
		{ name: "content-type", value: "application/json" },
		...
	],
	status: 403,
})
```

## The client

The first argument of `send_email!` and `send_template_email!` is a `SendGrid.Client`:

| Field | Default | |
| --- | --- | --- |
| `http_send!` | | The function that sends the HTTP request, like basic-cli's `Http.send!` |
| `api_key` | | The SendGrid API key |
| `timeout_ms` | `30_000` | How long a request may take, in milliseconds |
| `base_url` | `"https://api.sendgrid.com"` | EU regional subusers set it to `"https://api.eu.sendgrid.com"` |

Build it once with `SendGrid.init` and pass it to every send:

```roc
client = SendGrid.init({ http_send!: Http.send!, api_key, base_url: "https://api.eu.sendgrid.com" })
```

`http_send!` takes a `Request` of [roc-lang/http](https://github.com/roc-lang/http) and returns a `Try` whose `Ok` is a `Response` of the same package, like `Http.send!` of basic-cli does. Since you're passing in the `http_send!` effect you can make it do anything you'd like. You could limit it to certain URLs, log all requests, or not send requests at all like in [examples/dry_run.roc](examples/dry_run.roc).

## Building a request

```roc
receipt : SendGrid.EmailRequest
receipt = {
	from: { email: "noreply@example.com", name: Ok("Example") },
	to: [{ email: "user@example.com" }],
	bcc: [{ email: "archive@example.com" }],
	subject: "Your receipt",
	content: [{ mime_type: "text/html", value: html }],
}
```

| Field | Default | |
| --- | --- | --- |
| `name` of an address | `Err(Missing)` | `name: Ok("Name")` sets a display name |
| `cc`, `bcc` | `[]` | An empty list is left out of the payload |
| `reply_to` | `Err(Missing)` | `Ok({ email: ... })` sets one |
| `categories` | `[]` | For filtering in SendGrid's statistics |

Every recipient of a request gets the same email, and everyone in `to` and `cc` sees every address in both. Mail to people who should not see each other takes one request per recipient. So does template mail where each recipient has their own `dynamic_template_data`. We will support batch emailing in the future, please post an issue if that's a feature you'd like to see!

## API

### `send_email!`

Send a plain text or HTML email. Any 2xx answer is `Ok({ status, message_id })`, where `message_id` is SendGrid's `X-Message-Id` header, the id its [Event Webhook](https://www.twilio.com/docs/sendgrid/for-developers/tracking-events/event) and Email Activity know the email by. The errors are:

- `SendGridRejected({ status, headers, body })`: SendGrid answered with another status. `body` is its answer, which names the problem. `headers` are the answer's headers, like `X-RateLimit-Reset` on a 429, the Unix time at which the rate limit resets.
- `SendGridHttpFailed(err)`: `http_send!` failed, with its own error as `err`.

### `send_template_email!`

Send an email using a SendGrid [dynamic template](https://www.twilio.com/docs/sendgrid/ui/sending-email/how-to-send-an-email-with-dynamic-templates). `dynamic_template_data` is the value the template's variables are read from, usually a record, encoded with the builtin `Json` module. Pass `{}` to a template without variables. Fails like `send_email!`.

```roc
response = SendGrid.send_template_email!(
	client,
	{
		from: { email: "noreply@example.com" },
		to: [{ email: "user@example.com" }],
		template_id: "d-0123456789abcdef0123456789abcdef",
		dynamic_template_data: { subject: "Your weekly report", first_name: "Anna", video_count: 3 },
	},
)?
```

The subject comes from the Subject setting of the template in SendGrid, so a template request has no `subject` field. To set it per email, write `{{subject}}` in that setting and pass `subject` in the data, as above. SendGrid ignores a subject sent beside a template that has its own, and `{{subject}}` never reads one.

The data has to encode without failing, so data holding an `F32` or `F64`, which can be NaN or infinite, does not compile. The type error names `encode_f32` or `encode_f64`. Use `Dec` for fractional numbers.

## Testing

The unit tests are the `expect`s in `package/`, run with `roc test package/main.roc`. The integration tests are the apps in `tests/`, run through [roc-spec](https://github.com/niclas-ahden/roc-spec) with `./tests.roc`. Both want the dev shell (`nix develop`). Pass a substring to run only the matching tests, like `./tests.roc transport`.

`tests/openapi_schema_test.roc` validates every payload variant (full, minimal, multiple recipients, and templates with and without the optional fields) against the [SendGrid OpenAPI spec](https://github.com/twilio/sendgrid-oai) in `spec/`, using [roc-openapi](https://github.com/niclas-ahden/roc-openapi).

## Documentation

View the full API documentation at [https://niclas-ahden.github.io/roc-sendgrid/](https://niclas-ahden.github.io/roc-sendgrid/).
