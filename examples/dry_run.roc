## Sends an email through an `http_send!` hook that prints the request instead
## of performing it, so it runs without an API key and without a network. It
## shows what the hook receives. A hook like this one is also how you test
## code of your own that sends email.
##
## The README has the hook that really sends, through basic-cli's `Http.send!`.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.27.0/HZanbveSUDoJF8LypR663eH7PpaKEKG36eErEQzmV1Qs.tar.zst",
	sendgrid: "../package/main.roc",
}

import pf.Stdout
import sendgrid.SendGrid

main! = |_args| {
	client = SendGrid.init({ http_send!: print_instead_of_sending!, api_key: "SG.not-a-real-key" })

	response = SendGrid.send_email!(
		client,
		{
			from: { email: "noreply@example.com", name: Ok("Example") },
			to: [{ email: "user@example.com", name: Ok("User") }],
			subject: "Hello from Roc!",
			content: [{ mime_type: "text/plain", value: "Sent via roc-sendgrid." }],
		},
	)?

	Stdout.line!("Status: ${response.status.to_str()}, message id: ${response.message_id}")
}

print_instead_of_sending! = |request| {
	Stdout.line!("${Str.inspect(request.method)} ${request.uri}")?
	# The Authorization header carries the API key, which must never reach a
	# log, so a hook that prints requests leaves its value out.
	for header in request.headers {
		value = if header.name == "Authorization" "Bearer <redacted>" else header.value
		Stdout.line!("${header.name}: ${value}")?
	}
	Stdout.line!("Timeout: ${Str.inspect(request.timeout_ms)}")?
	Stdout.line!("")?
	Stdout.line!(Str.from_utf8_lossy(request.body))?
	Stdout.line!("")?

	# What SendGrid answers when it accepts an email: 202, an empty body and
	# the id it gave the email.
	Ok({ status: 202, headers: [{ name: "X-Message-Id", value: "dry-run-message-id" }], body: [] })
}
