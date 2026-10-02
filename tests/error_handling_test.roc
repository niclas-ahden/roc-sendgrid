## A response outside 2xx is a SendGridRejected error carrying the status,
## the headers and SendGrid's answer, not an Ok.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.27.0/HZanbveSUDoJF8LypR663eH7PpaKEKG36eErEQzmV1Qs.tar.zst",
	sendgrid: "../package/main.roc",
}

import sendgrid.SendGrid

## What SendGrid answers when the from address is not a verified sender.
unverified_sender_body = "{\"errors\":[{\"message\":\"The from address does not match a verified Sender Identity.\",\"field\":\"from\",\"help\":null}]}"

unverified_sender_headers = [{ name: "content-type", value: "application/json" }]

main! = |_args| {
	result = SendGrid.send_email!(
		{ http_send!: fake_http_send!, api_key: "SG.my-secret-key", timeout_ms: 30_000 },
		{
			from: { email: "s@test.com" },
			to: [{ email: "t@test.com" }],
			subject: "Test",
			content: [{ mime_type: "text/plain", value: "x" }],
		},
	)

	match result {
		Ok(_) => Err(ShouldHaveFailed)
		Err(SendGridRejected({ status: 403, headers, body })) if headers == unverified_sender_headers and body == unverified_sender_body => Ok({})
		Err(SendGridRejected(rejection)) => Err(WrongRejection(rejection))
		Err(SendGridHttpFailed(http_error)) => Err(ShouldHaveBeenRejected(http_error))
	}
}

fake_http_send! = |_request|
	Ok({ status: 403, headers: unverified_sender_headers, body: Str.to_utf8(unverified_sender_body) })
