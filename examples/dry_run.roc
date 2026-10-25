## Sends an email through an `http_send!` hook that prints the request instead
## of performing it, so it runs without an API key and without a network. It
## shows what the hook receives. A hook like this one is also how you test
## code of your own that sends email.
##
## examples/send.roc really sends, with basic-cli's `Http.send!` as the hook.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	sendgrid: "../package/main.roc",
}

import pf.Stdout
import http.Response
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
	Stdout.line!("${request.method_str()} ${request.uri()}")?
	# The Authorization header carries the API key, which must never reach a
	# log, so a hook that prints requests leaves its value out.
	for header in request.headers() {
		value = if header.name == "Authorization" "Bearer <redacted>" else header.value
		Stdout.line!("${header.name}: ${value}")?
	}
	Stdout.line!("Timeout: ${Str.inspect(request.timeout())}")?
	Stdout.line!("")?
	Stdout.line!(Str.from_utf8_lossy(request.body()))?
	Stdout.line!("")?

	# What SendGrid answers when it accepts an email: 202, an empty body and
	# the id it gave the email.
	Ok(Response.from_status(202).add_header("X-Message-Id", "dry-run-message-id"))
}
