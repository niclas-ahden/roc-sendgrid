## Sends one email through SendGrid with basic-cli's `Http.send!`. The API key
## comes from SENDGRID_API_KEY, the sender from SENDGRID_FROM and the
## recipient from SENDGRID_TO. The sender has to be a verified sender of the
## SendGrid account. Without SENDGRID_API_KEY it sends nothing.
##
## The README shows this app.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.27.0/HZanbveSUDoJF8LypR663eH7PpaKEKG36eErEQzmV1Qs.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	sendgrid: "../package/main.roc",
}

import pf.Env
import pf.Http
import pf.OsStr
import pf.Stdout
import http.Request
import http.Response
import sendgrid.SendGrid

main! = |_args|
	match env_var!("SENDGRID_API_KEY") {
		Err(_) => Stdout.line!("SENDGRID_API_KEY is not set, so nothing was sent.")
		Ok(api_key) => {
			client = SendGrid.init({ http_send!: http_send!, api_key })

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

# roc-sendgrid hands `http_send!` the request as a record, and basic-cli's
# `Http.send!` takes the roc-lang/http `Request` and returns its `Response`,
# so this converts the request into one and the answer back. The method is
# always POST.
http_send! = |req| {
	request =
		Request.from_method(POST)
			.with_uri(req.uri)
			.with_body(req.body)
			.with_timeout(req.timeout_ms)
	response = Http.send!(req.headers.fold(request, |acc, header| acc.add_header(header.name, header.value)))?

	Ok({
		status: Response.status(response),
		headers: Response.headers(response).map(|header| { name: header.name, value: header.value }),
		body: Response.body(response),
	})
}
