## send_email! and send_template_email! both send a POST to the mail send
## endpoint under the client's base URL, with the client's API key as a
## bearer token, a JSON content type and the client's timeout. A client that
## leaves out the base URL and the timeout gets SendGrid's global API and 30
## seconds. The fake http_send! hook refuses anything else, and answers 202
## with a message id like SendGrid does, which both send functions return.
## The OpenAPI test covers the payload and this covers everything else.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.27.0/HZanbveSUDoJF8LypR663eH7PpaKEKG36eErEQzmV1Qs.tar.zst",
	sendgrid: "../package/main.roc",
}

import sendgrid.SendGrid

main! = |_args| {
	client = SendGrid.init({
		http_send!: |request| fake_http_send!({ uri: "https://api.sendgrid.com/v3/mail/send", timeout_ms: 30_000 }, request),
		api_key: "SG.my-secret-key",
	})

	sent = SendGrid.send_email!(client, email) ? |e| EmailFailed(e)

	sent_template = SendGrid.send_template_email!(
		client,
		{
			from: { email: "s@test.com" },
			to: [{ email: "t@test.com" }],
			template_id: "d-abc123",
			dynamic_template_data: {},
		},
	) ? |e| TemplateEmailFailed(e)

	# Without init, a client is a record literal bound to an annotated name.
	eu_client : SendGrid.Client(_)
	eu_client = {
		http_send!: |request| fake_http_send!({ uri: "https://api.eu.sendgrid.com/v3/mail/send", timeout_ms: 15_000 }, request),
		api_key: "SG.my-secret-key",
		timeout_ms: 15_000,
		base_url: "https://api.eu.sendgrid.com",
	}

	sent_eu = SendGrid.send_email!(eu_client, email) ? |e| EuEmailFailed(e)

	expected = { status: 202, message_id: "msg-1" }
	if sent != expected {
		Err(UnexpectedEmailResponse(sent))
	} else if sent_template != expected {
		Err(UnexpectedTemplateEmailResponse(sent_template))
	} else if sent_eu != expected {
		Err(UnexpectedEuEmailResponse(sent_eu))
	} else {
		Ok({})
	}
}

email : SendGrid.EmailRequest
email = {
	from: { email: "s@test.com" },
	to: [{ email: "t@test.com" }],
	subject: "Test",
	content: [{ mime_type: "text/plain", value: "x" }],
}

fake_http_send! = |expected, request|
	if request.uri != expected.uri {
		Err(WrongUrl(request.uri))
	} else if request.method != POST {
		Err(WrongMethod)
	} else if !(request.headers.any(|h| h.name == "Authorization" and h.value == "Bearer SG.my-secret-key")) {
		Err(WrongAuth)
	} else if !(request.headers.any(|h| h.name == "Content-Type" and h.value == "application/json")) {
		Err(MissingContentType)
	} else if request.timeout_ms != TimeoutMilliseconds(expected.timeout_ms) {
		Err(WrongTimeout(request.timeout_ms))
	} else {
		Ok({ status: 202, headers: [{ name: "X-Message-Id", value: "msg-1" }], body: [] })
	}
