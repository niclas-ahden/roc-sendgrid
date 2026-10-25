## A failing http_send! hook (the request never got an answer) is a
## SendGridHttpFailed error carrying the hook's own error.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	sendgrid: "../package/main.roc",
}

import sendgrid.SendGrid

main! = |_args| {
	result = SendGrid.send_email!(
		{ http_send!: fake_http_send!, api_key: "SG.test", timeout_ms: 30_000 },
		{
			from: { email: "s@t.com" },
			to: [{ email: "r@t.com" }],
			subject: "X",
			content: [{ mime_type: "text/plain", value: "x" }],
		},
	)

	match result {
		Ok(_) => Err(ShouldHaveFailed)
		Err(SendGridHttpFailed(ConnectionTimeout)) => Ok({})
		Err(SendGridRejected(rejection)) => Err(ShouldHaveFailedToSend(rejection))
	}
}

fake_http_send! = |_request|
	Err(ConnectionTimeout)
