## Every payload variant roc-sendgrid produces (full, minimal, multiple
## recipients, and templates with and without the optional fields) conforms
## to the SendGrid OpenAPI spec in spec/tsg_mail_v3.json. Each email is sent
## through an http_send! hook that validates the request body with
## roc-openapi instead of sending it.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	sendgrid: "../package/main.roc",
	openapi: "https://github.com/niclas-ahden/roc-openapi/releases/download/0.2.1/5fQEMmB1UxbMjEPV8QLzz5qztEM9dvCLtG93KHsYYZ8g.tar.zst",
}

import pf.Stdout

import http.Response

import openapi.OpenApi

import sendgrid.SendGrid

import "../spec/tsg_mail_v3.json" as spec_source : Str

## Full email with every optional field set.
full_email : SendGrid.EmailRequest
full_email = {
	from: { email: "sender@example.com", name: Ok("Sender") },
	to: [{ email: "to@example.com", name: Ok("Recipient") }],
	cc: [{ email: "cc@example.com" }],
	bcc: [{ email: "bcc@example.com" }],
	reply_to: Ok({ email: "reply@example.com" }),
	subject: "Full email test",
	content: [
		{ mime_type: "text/plain", value: "Plain text" },
		{ mime_type: "text/html", value: "<p>HTML</p>" },
	],
	categories: ["Receipts", "Monthly"],
}

## Minimal email with every optional field left out.
minimal_email : SendGrid.EmailRequest
minimal_email = {
	from: { email: "sender@example.com" },
	to: [{ email: "to@example.com" }],
	subject: "Minimal",
	content: [{ mime_type: "text/plain", value: "Hello" }],
}

## Multiple recipients.
multi_email : SendGrid.EmailRequest
multi_email = {
	from: { email: "sender@example.com" },
	to: [
		{ email: "alice@example.com", name: Ok("Alice") },
		{ email: "bob@example.com", name: Ok("Bob") },
	],
	cc: [{ email: "cc@example.com" }],
	bcc: [{ email: "bcc@example.com" }],
	subject: "Multi",
	content: [{ mime_type: "text/plain", value: "Hello all" }],
}

## Template email with only the required fields.
template_email : SendGrid.TemplateEmailRequest({ name : Str })
template_email = {
	from: { email: "sender@example.com" },
	to: [{ email: "to@example.com" }],
	template_id: "d-abc123",
	dynamic_template_data: { name: "Anna" },
}

## Template email with every optional field set.
full_template_email : SendGrid.TemplateEmailRequest({ subject : Str, count : U8 })
full_template_email = {
	from: { email: "sender@example.com", name: Ok("Sender") },
	to: [{ email: "to@example.com", name: Ok("Recipient") }],
	cc: [{ email: "cc@example.com" }],
	bcc: [{ email: "bcc@example.com" }],
	reply_to: Ok({ email: "reply@example.com" }),
	template_id: "d-abc123",
	dynamic_template_data: { subject: "Template", count: 3 },
	categories: ["Lead"],
}

main! = |_args| {
	api = OpenApi.parse(spec_source.to_utf8())?
	client = SendGrid.init({
		http_send!: |request| validate_instead_of_sending!(api, request),
		api_key: "SG.test",
	})

	# Each failure gets its own tag, so the run says which payload was
	# rejected. The error carries the schema errors.
	_ = SendGrid.send_email!(client, full_email) ? |e| FullEmailRejected(e)
	_ = SendGrid.send_email!(client, minimal_email) ? |e| MinimalEmailRejected(e)
	_ = SendGrid.send_email!(client, multi_email) ? |e| MultiEmailRejected(e)
	_ = SendGrid.send_template_email!(client, template_email) ? |e| TemplateEmailRejected(e)
	_ = SendGrid.send_template_email!(client, full_template_email) ? |e| FullTemplateEmailRejected(e)

	Stdout.line!("All payloads validated against SendGrid OpenAPI spec")
}

## Fake http_send! that answers 202 when the request is valid against the
## SendGrid spec: its URL and method name an operation in it, its
## Content-Type is one that operation takes, and its body fits that media
## type's schema. An `Err(Missing)` that leaked into the JSON as text is
## refused before that.
validate_instead_of_sending! = |api, request| {
	body_str = Str.from_utf8_lossy(request.body())

	if body_str.contains("Missing") {
		Err(MissingLeaked(body_str))
	} else {
		content_type =
			request.headers()
				.find_first(|h| h.name == "Content-Type")
				.map_ok(|h| h.value)
				.ok_or("")

		match api.validate_request({ method: request.method_str(), path: request.uri(), content_type, body: request.body() }) {
			Ok({}) => Ok(Response.from_status(202))
			Err(Invalid(errors)) => Err(SchemaValidationFailed(errors.map(|error| error.to_str())))
			Err(setup_error) => Err(ValidationSetupFailed(Str.inspect(setup_error)))
		}
	}
}
