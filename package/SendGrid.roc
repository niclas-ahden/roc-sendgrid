import http.Request
# Renamed because SendGrid.Response is the answer this package returns.
import http.Response as HttpResponse

## SendGrid v3 mail send API client.
##
## The package cannot import platform modules, so the platform's HTTP send
## arrives in a [SendGrid.Client], the first argument of every effectful
## function, together with the API key:
##
## ```
## client = SendGrid.init({ http_send!: Http.send!, api_key: key })
## SendGrid.send_email!(client, email)?
## ```
##
## `http_send!` takes a `Request` of
## [roc-lang/http](https://github.com/roc-lang/http) and returns a `Try`
## whose `Ok` is a `Response` of the same package. basic-cli's `Http.send!` is
## one, so it is passed as is. It can also be a function of the app, one that
## logs, limits or fakes what is sent.
##
## The optional fields of [SendGrid.Client], [SendGrid.EmailAddress],
## [SendGrid.EmailRequest] and [SendGrid.TemplateEmailRequest] have defaults,
## so a record leaves out what it does not use. These are nominal types, and a
## record literal becomes one only where its type is known: passed straight
## to a function that takes one, or bound to a name with a type annotation.
##
## The request payload is built as JSON text by hand because the SendGrid
## schema needs a "type" key, which is not a legal Roc field name.
SendGrid := [].{

	## How to reach SendGrid. `http_send!` sends the HTTP request, see the
	## module docs, and `api_key` is the SendGrid API key.
	##
	## `timeout_ms` is how long a request may take, in milliseconds. A request
	## that blocks something else, like a web request handler, wants a shorter
	## one than the default.
	##
	## `base_url` is where the API is. EU regional subusers set it to
	## `"https://api.eu.sendgrid.com"`. A trailing slash is ignored.
	##
	## `send` is the type of `http_send!`, which is left to the compiler.
	## [SendGrid.init] builds a client.
	Client(send) := {
		http_send! : send,
		api_key : Str,
		timeout_ms : U64 ?? 30_000,
		base_url : Str ?? "https://api.sendgrid.com",
	}

	## A client with the given fields and the defaults for those left out:
	##
	## ```
	## client = SendGrid.init({ http_send!: Http.send!, api_key: key })
	## eu_client = SendGrid.init({ http_send!: Http.send!, api_key: key, base_url: "https://api.eu.sendgrid.com" })
	## ```
	##
	## `init` returns the record it is given. What it adds is a type. Roc gives
	## a record literal the defaults of [SendGrid.Client] only where it knows
	## the literal is a client, and anywhere else the literal stays a plain
	## record without `timeout_ms` and `base_url`, so passing it on is a type
	## mismatch. The argument of `init` is a client wherever the call is.
	##
	## A literal is also a client when it is passed straight to
	## [SendGrid.send_email!], or bound to a name annotated
	## `client : SendGrid.Client(_)`, and needs no `init` there. Where neither
	## fits, like a client built inside another record, `init` is the way:
	##
	## ```
	## deps = {
	##     db,
	##     mailer: SendGrid.init({ http_send!: Http.send!, api_key: key }),
	## }
	## ```
	init : SendGrid.Client(send) -> SendGrid.Client(send)
	# The body does nothing on purpose. The parameter type is what makes the
	# compiler read the argument as a client and fill in its defaults.
	init = |client| client

	## Email address with an optional display name. `{ email: "a@example.com" }`
	## has no name and `{ email: "a@example.com", name: Ok("A") }` has one.
	EmailAddress := {
		email : Str,
		name : Try(Str, [Missing]) ?? Err(Missing),
	}

	## One body of an email, like `{ mime_type: "text/html", value: html }`.
	## `mime_type` is sent as the JSON "type" key. SendGrid refuses an email
	## whose "text/html" comes before its "text/plain", so the payload puts
	## "text/plain" first and "text/html" next, whatever the order in
	## `content`.
	EmailContent : { mime_type : Str, value : Str }

	## An email with its own subject and content. `cc`, `bcc`, `reply_to` and
	## `categories` can be left out, and an empty list is left out of the
	## payload.
	##
	## Every recipient of a request gets the same email, and everyone in `to`
	## and `cc` sees every address in both. Mail to people who should not see
	## each other takes one request per recipient. So does template mail
	## where each recipient has their own `dynamic_template_data`.
	EmailRequest := {
		from : SendGrid.EmailAddress,
		to : List(SendGrid.EmailAddress),
		cc : List(SendGrid.EmailAddress) ?? [],
		bcc : List(SendGrid.EmailAddress) ?? [],
		reply_to : Try(SendGrid.EmailAddress, [Missing]) ?? Err(Missing),
		subject : Str,
		content : List(SendGrid.EmailContent),
		categories : List(Str) ?? [],
	}

	## An email rendered by a SendGrid dynamic template, whose id starts with
	## "d-". `dynamic_template_data` is the value the template's variables are
	## read from, usually a record, encoded with the builtin Json module. Pass
	## `{}` to a template without variables. `cc`, `bcc`, `reply_to` and
	## `categories` can be left out, and recipients see each other the way
	## [SendGrid.EmailRequest] describes.
	##
	## The subject comes from the Subject setting of the template in SendGrid,
	## so a request has no `subject` field. To set it per email, write
	## `{{subject}}` there and pass the subject in the data, like
	## `dynamic_template_data: { subject: "Your receipt", total: 120 }`.
	## SendGrid ignores a subject sent beside a template that has its own, and
	## `{{subject}}` never reads one.
	##
	## The data has to encode without failing, so data holding an F32 or F64,
	## which can be NaN or infinite, does not compile. The type error names
	## `encode_f32` or `encode_f64`. Use Dec for fractional numbers.
	TemplateEmailRequest(data) := {
		from : SendGrid.EmailAddress,
		to : List(SendGrid.EmailAddress),
		cc : List(SendGrid.EmailAddress) ?? [],
		bcc : List(SendGrid.EmailAddress) ?? [],
		reply_to : Try(SendGrid.EmailAddress, [Missing]) ?? Err(Missing),
		template_id : Str,
		dynamic_template_data : data,
		categories : List(Str) ?? [],
	}

	## SendGrid's answer to an email it accepted. `message_id` is its
	## `X-Message-Id` header, the id that the Event Webhook and Email Activity
	## know the email by, and `""` in an answer without one.
	Response : { status : U16, message_id : Str }

	## SendGrid's answer to an email it refused. `body` says what it refused,
	## usually as JSON with an "errors" list. `headers` are the answer's
	## headers, like `X-RateLimit-Reset` on a 429, the Unix time at which the
	## rate limit resets.
	Rejection : { status : U16, headers : List({ name : Str, value : Str }), body : Str }

	# The signatures of send_email! and send_template_email! stay on one line,
	# because `roc docs` drops the doc comment of a signature that is wrapped
	# over several lines.

	## Send an email via SendGrid. Any 2xx status is `Ok`. Any other status is
	## `Err(SendGridRejected(rejection))` with SendGrid's answer, see
	## [SendGrid.Rejection]. A failed `http_send!` is
	## `Err(SendGridHttpFailed(err))` with the hook's own error.
	send_email! : SendGrid.Client(_), SendGrid.EmailRequest => Try(SendGrid.Response, [SendGridRejected(SendGrid.Rejection), SendGridHttpFailed(_)])
	send_email! = |client, email_request|
		send_request!(client, SendGrid.email_request_json(email_request))

	## Send an email using a SendGrid dynamic template. Succeeds and fails
	## like [SendGrid.send_email!].
	send_template_email! : SendGrid.Client(_), SendGrid.TemplateEmailRequest(data) => Try(SendGrid.Response, [SendGridRejected(SendGrid.Rejection), SendGridHttpFailed(_)])
		where [data.Json.Encodable([])]
	send_template_email! = |client, req|
		send_request!(client, SendGrid.template_request_json(req))

	## The JSON payload for [SendGrid.send_email!]. Public so it can be
	## tested without performing IO.
	email_request_json : SendGrid.EmailRequest -> Str
	email_request_json = |req| {
		personalization = object(
			recipient_fields(req.to, req.cc, req.bcc)
				.append(Ok(("subject", json_str(req.subject)))),
		)

		object([
			Ok(("personalizations", "[${personalization}]")),
			Ok(("from", address_json(req.from))),
			Ok(("content", json_list(sendgrid_order(req.content), content_json))),
			req.reply_to.map_ok(|a| ("reply_to", address_json(a))),
			non_empty("categories", req.categories, json_str),
		])
	}

	## The JSON payload for [SendGrid.send_template_email!]. Public so it can
	## be tested without performing IO.
	template_request_json : SendGrid.TemplateEmailRequest(data) -> Str where [data.Json.Encodable([])]
	template_request_json = |req| {
		personalization = object(
			recipient_fields(req.to, req.cc, req.bcc)
				.append(Ok(("dynamic_template_data", Json.to_str(req.dynamic_template_data)))),
		)

		object([
			Ok(("personalizations", "[${personalization}]")),
			Ok(("from", address_json(req.from))),
			Ok(("template_id", json_str(req.template_id))),
			req.reply_to.map_ok(|a| ("reply_to", address_json(a))),
			non_empty("categories", req.categories, json_str),
		])
	}
}

## JSON-encode a string (quotes and escapes included).
json_str : Str -> Str
json_str = |s| Json.to_str(s)

## A JSON array of the items, each encoded by `encode`.
json_list : List(a), (a -> Str) -> Str
json_list = |items, encode|
	"[${Str.join_with(items.map(encode), ",")}]"

## Build a JSON object from optional ("key", encoded_value) pairs, skipping
## the Err(Missing) ones.
object : List(Try((Str, Str), [Missing])) -> Str
object = |fields| {
	parts = fields.fold(
		[],
		|acc, field|
			match field {
				Ok((key, value)) => acc.append("${json_str(key)}:${value}")
				Err(Missing) => acc
			},
	)
	"{${Str.join_with(parts, ",")}}"
}

## A ("key", JSON array) pair for `object`, or `Err(Missing)` for an empty
## list, so the payload never carries an empty array.
non_empty : Str, List(a), (a -> Str) -> Try((Str, Str), [Missing])
non_empty = |key, items, encode|
	if items.is_empty() {
		Err(Missing)
	} else {
		Ok((key, json_list(items, encode)))
	}

## The to, cc and bcc fields of a personalization.
recipient_fields :
	List(SendGrid.EmailAddress),
	List(SendGrid.EmailAddress),
	List(SendGrid.EmailAddress)
	-> List(Try((Str, Str), [Missing]))
recipient_fields = |to, cc, bcc| [
	Ok(("to", json_list(to, address_json))),
	non_empty("cc", cc, address_json),
	non_empty("bcc", bcc, address_json),
]

address_json : SendGrid.EmailAddress -> Str
address_json = |a|
	object([
		Ok(("email", json_str(a.email))),
		a.name.map_ok(|n| ("name", json_str(n))),
	])

## The content in the order SendGrid accepts: "text/plain", then
## "text/html", then the rest in the order given.
sendgrid_order : List(SendGrid.EmailContent) -> List(SendGrid.EmailContent)
sendgrid_order = |content| {
	plain = content.keep_if(|c| c.mime_type == "text/plain")
	html = content.keep_if(|c| c.mime_type == "text/html")
	rest = content.drop_if(|c| c.mime_type == "text/plain" or c.mime_type == "text/html")
	plain.concat(html).concat(rest)
}

content_json : SendGrid.EmailContent -> Str
content_json = |c|
	object([
		Ok(("type", json_str(c.mime_type))),
		Ok(("value", json_str(c.value))),
	])

## The HTTP request for a given JSON payload.
build_request : Str, { api_key : Str, timeout_ms : U64, base_url : Str } -> Request
build_request = |body_json, { api_key, timeout_ms, base_url }|
	Request.from_method(POST)
		.with_uri("${base_url.drop_suffix("/")}/v3/mail/send")
		.add_header("Authorization", "Bearer ${api_key}")
		.add_header("Content-Type", "application/json")
		.with_body(Str.to_utf8(body_json))
		.with_timeout(TimeoutMilliseconds(timeout_ms))

## Map the outcome of the HTTP send (the response on success, the transport
## error otherwise) to the package's result type. Any 2xx status is a
## success.
interpret_send_result :
	Try(HttpResponse, err)
	-> Try(SendGrid.Response, [SendGridRejected(SendGrid.Rejection), SendGridHttpFailed(err)])
interpret_send_result = |result|
	match result {
		Ok(response) => {
			status = response.status()
			headers = response.headers().map(|header| { name: header.name, value: header.value })
			if status >= 200 and status < 300 {
				Ok({ status, message_id: header_value(headers, "X-Message-Id") })
			} else {
				Err(SendGridRejected({ status, headers, body: Str.from_utf8_lossy(response.body()) }))
			}
		}
		Err(http_error) =>
			Err(SendGridHttpFailed(http_error))
	}

## Send pre-built JSON to the SendGrid API.
send_request! = |client, body_json| {
	# `client.http_send!(request)` would be a method call on the record, so
	# the field is bound to a name first.
	http_send! = client.http_send!
	request = build_request(body_json, { api_key: client.api_key, timeout_ms: client.timeout_ms, base_url: client.base_url })
	# A match rather than passing the answer on: the hook may return a
	# structural Ok/Err union, which is not a Try.
	match http_send!(request) {
		Ok(response) => interpret_send_result(Ok(response))
		Err(http_error) => interpret_send_result(Err(http_error))
	}
}

## The value of the first header called `name`, which is compared ignoring
## case as HTTP header names are, or `""` when there is none.
header_value : List({ name : Str, value : Str }), Str -> Str
header_value = |headers, name|
	headers
		.find_first(|header| header.name.caseless_ascii_equals(name))
		.map_ok(|header| header.value)
		.ok_or("")

expect {
	minimal : SendGrid.EmailRequest
	minimal = {
		from: { email: "from@example.com" },
		to: [{ email: "to@example.com", name: Ok("To Person") }],
		subject: "Hello",
		content: [{ mime_type: "text/plain", value: "Hi there" }],
	}
	output = SendGrid.email_request_json(minimal)
	expected = "{\"personalizations\":[{\"to\":[{\"email\":\"to@example.com\",\"name\":\"To Person\"}],\"subject\":\"Hello\"}],\"from\":{\"email\":\"from@example.com\"},\"content\":[{\"type\":\"text/plain\",\"value\":\"Hi there\"}]}"
	output == expected
}

expect {
	full : SendGrid.EmailRequest
	full = {
		from: { email: "from@example.com", name: Ok("Sender") },
		to: [{ email: "a@example.com" }, { email: "b@example.com", name: Ok("B") }],
		cc: [{ email: "cc@example.com" }],
		bcc: [{ email: "bcc@example.com" }],
		reply_to: Ok({ email: "reply@example.com" }),
		subject: "Quoted \"subject\"",
		content: [{ mime_type: "text/html", value: "<b>Hi</b>" }],
		categories: ["Receipts", "Monthly"],
	}
	output = SendGrid.email_request_json(full)
	expected = "{\"personalizations\":[{\"to\":[{\"email\":\"a@example.com\"},{\"email\":\"b@example.com\",\"name\":\"B\"}],\"cc\":[{\"email\":\"cc@example.com\"}],\"bcc\":[{\"email\":\"bcc@example.com\"}],\"subject\":\"Quoted \\\"subject\\\"\"}],\"from\":{\"email\":\"from@example.com\",\"name\":\"Sender\"},\"content\":[{\"type\":\"text/html\",\"value\":\"<b>Hi</b>\"}],\"reply_to\":{\"email\":\"reply@example.com\"},\"categories\":[\"Receipts\",\"Monthly\"]}"
	output == expected
}

# Empty cc, bcc and categories lists are left out, not sent as [].
expect {
	empty_lists : SendGrid.EmailRequest
	empty_lists = {
		from: { email: "from@example.com" },
		to: [{ email: "to@example.com" }],
		cc: [],
		bcc: [],
		subject: "Hello",
		content: [{ mime_type: "text/plain", value: "Hi" }],
		categories: [],
	}
	output = SendGrid.email_request_json(empty_lists)
	expected = "{\"personalizations\":[{\"to\":[{\"email\":\"to@example.com\"}],\"subject\":\"Hello\"}],\"from\":{\"email\":\"from@example.com\"},\"content\":[{\"type\":\"text/plain\",\"value\":\"Hi\"}]}"
	output == expected
}

# Content goes out as text/plain, text/html, then the rest, whatever the
# order it was given in.
expect {
	html_first : SendGrid.EmailRequest
	html_first = {
		from: { email: "from@example.com" },
		to: [{ email: "to@example.com" }],
		subject: "Hello",
		content: [
			{ mime_type: "text/html", value: "<b>Hi</b>" },
			{ mime_type: "text/calendar", value: "BEGIN:VCALENDAR" },
			{ mime_type: "text/plain", value: "Hi" },
		],
	}
	output = SendGrid.email_request_json(html_first)
	expected = "{\"personalizations\":[{\"to\":[{\"email\":\"to@example.com\"}],\"subject\":\"Hello\"}],\"from\":{\"email\":\"from@example.com\"},\"content\":[{\"type\":\"text/plain\",\"value\":\"Hi\"},{\"type\":\"text/html\",\"value\":\"<b>Hi</b>\"},{\"type\":\"text/calendar\",\"value\":\"BEGIN:VCALENDAR\"}]}"
	output == expected
}

# Newlines, tabs, control characters, backslashes and non-ASCII text come out
# as valid JSON. Non-ASCII text is sent as UTF-8, not as \u escapes.
expect {
	escapes : SendGrid.EmailRequest
	escapes = {
		from: { email: "from@example.com", name: Ok("Åsa \\ Öberg") },
		to: [{ email: "to@example.com" }],
		subject: "Tab\there 🎉 \u(01)",
		content: [{ mime_type: "text/plain", value: "Line one\nLine two\r\nEnd" }],
	}
	output = SendGrid.email_request_json(escapes)
	expected = "{\"personalizations\":[{\"to\":[{\"email\":\"to@example.com\"}],\"subject\":\"Tab\\there 🎉 \\u0001\"}],\"from\":{\"email\":\"from@example.com\",\"name\":\"Åsa \\\\ Öberg\"},\"content\":[{\"type\":\"text/plain\",\"value\":\"Line one\\nLine two\\r\\nEnd\"}]}"
	output == expected
}

expect {
	templated : SendGrid.TemplateEmailRequest({ video_count : U8 })
	templated = {
		from: { email: "from@example.com" },
		to: [{ email: "to@example.com" }],
		template_id: "d-456",
		dynamic_template_data: { video_count: 3 },
	}
	expected = "{\"personalizations\":[{\"to\":[{\"email\":\"to@example.com\"}],\"dynamic_template_data\":{\"video_count\":3}}],\"from\":{\"email\":\"from@example.com\"},\"template_id\":\"d-456\"}"
	SendGrid.template_request_json(templated) == expected
}

# The template data is encoded by the Json module, so a string in it is
# escaped like any other.
expect {
	templated : SendGrid.TemplateEmailRequest({ name : Str })
	templated = {
		from: { email: "from@example.com", name: Ok("Sender") },
		to: [{ email: "to@example.com" }],
		cc: [{ email: "cc@example.com" }],
		reply_to: Ok({ email: "reply@example.com" }),
		template_id: "d-456",
		dynamic_template_data: { name: "Anna \"A\"" },
		categories: ["Lead"],
	}
	expected = "{\"personalizations\":[{\"to\":[{\"email\":\"to@example.com\"}],\"cc\":[{\"email\":\"cc@example.com\"}],\"dynamic_template_data\":{\"name\":\"Anna \\\"A\\\"\"}}],\"from\":{\"email\":\"from@example.com\",\"name\":\"Sender\"},\"template_id\":\"d-456\",\"reply_to\":{\"email\":\"reply@example.com\"},\"categories\":[\"Lead\"]}"
	SendGrid.template_request_json(templated) == expected
}

expect {
	no_variables : SendGrid.TemplateEmailRequest({})
	no_variables = {
		from: { email: "from@example.com" },
		to: [{ email: "to@example.com" }],
		template_id: "d-789",
		dynamic_template_data: {},
	}
	expected = "{\"personalizations\":[{\"to\":[{\"email\":\"to@example.com\"}],\"dynamic_template_data\":{}}],\"from\":{\"email\":\"from@example.com\"},\"template_id\":\"d-789\"}"
	SendGrid.template_request_json(no_variables) == expected
}

# build_request: where the request goes and what it carries.

client_settings = { api_key: "SG.key", timeout_ms: 15_000, base_url: "https://api.sendgrid.com" }

expect build_request("{}", client_settings).uri() == "https://api.sendgrid.com/v3/mail/send"

expect build_request("{}", { ..client_settings, base_url: "https://api.eu.sendgrid.com" }).uri() == "https://api.eu.sendgrid.com/v3/mail/send"

expect build_request("{}", { ..client_settings, base_url: "http://localhost:8080/" }).uri() == "http://localhost:8080/v3/mail/send"

expect build_request("{}", client_settings).method_str() == "POST"

expect build_request("{}", client_settings).headers().map(|header| header.to_str()) == [
	"Authorization: Bearer SG.key",
	"Content-Type: application/json",
]

expect build_request("{\"x\":1}", client_settings).body() == Str.to_utf8("{\"x\":1}")

expect build_request("{}", client_settings).timeout() == TimeoutMilliseconds(15_000)

# A client that leaves out timeout_ms and base_url gets the defaults.
expect {
	client : SendGrid.Client(_)
	client = { http_send!: |_request| Err(NeverCalled), api_key: "SG.key" }
	client.timeout_ms == 30_000 and client.base_url == "https://api.sendgrid.com"
}

# So does one that init builds in place, here as a field of another record.
expect {
	deps = { mailer: SendGrid.init({ http_send!: |_request| Err(NeverCalled), api_key: "SG.key", base_url: "https://api.eu.sendgrid.com" }) }
	deps.mailer.timeout_ms == 30_000 and deps.mailer.base_url == "https://api.eu.sendgrid.com"
}

# interpret_send_result: any 2xx status is a success carrying the status and
# the message id.

expect {
	ok : Try(HttpResponse, [NoTransportError])
	ok = Ok(HttpResponse.from_status(202).add_header("X-Message-Id", "abc123"))
	interpret_send_result(ok) == Ok({ status: 202, message_id: "abc123" })
}

expect {
	ok : Try(HttpResponse, [NoTransportError])
	ok = Ok(HttpResponse.from_status(200))
	interpret_send_result(ok) == Ok({ status: 200, message_id: "" })
}

expect {
	ok : Try(HttpResponse, [NoTransportError])
	ok = Ok(HttpResponse.from_status(299))
	interpret_send_result(ok) == Ok({ status: 299, message_id: "" })
}

# Header names are compared ignoring case, as HTTP/2 sends them in lowercase.
expect {
	ok : Try(HttpResponse, [NoTransportError])
	ok = Ok(HttpResponse.from_status(202).add_header("content-length", "0").add_header("x-message-id", "abc123"))
	interpret_send_result(ok) == Ok({ status: 202, message_id: "abc123" })
}

# Every other status is a rejection carrying the status, the headers and
# SendGrid's body.

expect {
	informational : Try(HttpResponse, [NoTransportError])
	informational = Ok(HttpResponse.from_status(199))
	interpret_send_result(informational) == Err(SendGridRejected({ status: 199, headers: [], body: "" }))
}

expect {
	redirect : Try(HttpResponse, [NoTransportError])
	redirect = Ok(HttpResponse.from_status(300))
	interpret_send_result(redirect) == Err(SendGridRejected({ status: 300, headers: [], body: "" }))
}

expect {
	forbidden : Try(HttpResponse, [NoTransportError])
	forbidden = Ok(HttpResponse.from_status(403).with_body(Str.to_utf8("{\"errors\":[{\"message\":\"The from address does not match a verified Sender Identity.\"}]}")))
	interpret_send_result(forbidden) == Err(SendGridRejected({ status: 403, headers: [], body: "{\"errors\":[{\"message\":\"The from address does not match a verified Sender Identity.\"}]}" }))
}

# The headers come along as they are, so a caller can read when a rate limit
# resets.
expect {
	rate_limited : Try(HttpResponse, [NoTransportError])
	rate_limited = Ok(HttpResponse.from_status(429).add_header("x-ratelimit-reset", "1790000000"))
	interpret_send_result(rate_limited) == Err(SendGridRejected({ status: 429, headers: [{ name: "x-ratelimit-reset", value: "1790000000" }], body: "" }))
}

# A transport error is passed on as it is.

expect {
	failed : Try(HttpResponse, [ConnectionTimeout])
	failed = Err(ConnectionTimeout)
	interpret_send_result(failed) == Err(SendGridHttpFailed(ConnectionTimeout))
}
