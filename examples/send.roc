## Sends one email through SendGrid with basic-cli's `Http.send!`. The API key
## comes from SENDGRID_API_KEY, the sender from SENDGRID_FROM and the
## recipient from SENDGRID_TO. The sender has to be a verified sender of the
## SendGrid account. Without SENDGRID_API_KEY it sends nothing.
##
## The README shows this app.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	sendgrid: "../package/main.roc",
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
			client = SendGrid.init({ http_send!: |request| Http.send!(request, {}), api_key })

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
