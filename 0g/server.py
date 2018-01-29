import os, cgi, sys
from SimpleHTTPServer import SimpleHTTPRequestHandler
from SocketServer import TCPServer

ROOT_DIR = os.getcwd()
MAIN_DIR = os.path.dirname(os.path.realpath(sys.argv[0]))
os.chdir(MAIN_DIR)
b_RUNNING = True

s_INTERFACE = ""
n_PORT = 80

global file_CFG

t_ROUTES = [
	("/","/www/index.html"),
	("/cmd","/www/command.html"),
	("/output","/www/output.txt"),
	("/server-log","/serverlog.txt"),
	("/payload-log","/log.txt"),
	("/shutdown","/www/shutdown.html"),
	("/payloads","/www/payloads.html"),
	("/config","/www/config.html"),
	("/error","/www/error.html"),
	("/font-awesome-min.css","/www/font-awesome-min.css"),
	("/bootstrap-iso.css","/www/bootstrap-iso.css"),
	("/popswrt.css","/www/popswrt.css"),
	("/favicon.ico","/www/popswrt.ico")
]

def f_URL_TO_PATH(_URL):
	_endURL = ""
	for i, d in t_ROUTES:
		if _URL.endswith(i):
			_endURL = d
			break
	if _endURL == "":
		_endURL = "/www/error.html"
	return _endURL

def f_ADD_CFG(_KEY,_VALUE):
	file_CFG.write(_KEY + "='" + _VALUE + "'\n")

class c_HANDLER(SimpleHTTPRequestHandler):

	def do_HEAD(self):
		self.send_response(200)
		if s_PATH.endswith(".css"):
			self.send_header("Content-type","text/css")
		elif s_PATH.endswith(".html"):
			self.send_header("Content-type","text/html")
		elif s_PATH.endswith(".ico"):
			self.send_header("Content-type","image/vnd.microsoft.icon")
		else:
			self.send_header("Content-type","text/plain")
		self.end_headers()

	def do_GET(self):
		try:
			global s_PATH
			s_PATH = f_URL_TO_PATH(self.path)
			self.do_HEAD()
			if self.path == "/payload-log":
				print("Request for payload log")
			elif self.path == "/server-log":
				print("Request for server log")
			else:
				print("Request: " + self.path)
				print("Resolved to: " + MAIN_DIR + s_PATH)
			f = open(MAIN_DIR + s_PATH,"r")
			self.wfile.write(f.read())
			f.close()
			if s_PATH.endswith("/shutdown.html"):
				print("Request to shutdown")
				global b_RUNNING
				b_RUNNING = False
				f = open(MAIN_DIR + "/CMD_SHUTDOWN","w")
				f.close()
				
		except IOError:
			self.send_response(200)
			self.send_header("Content-type","text/html")
			self.end_headers()
			f = open(MAIN_DIR + "/www/index.html","r")
			self.wfile.write(f.read())
			f.close()
		
	def do_POST(self):
		global s_PATH
		s_PATH = f_URL_TO_PATH(self.path)
		print("POST Request: " + self.path)
		print("Resolved to: " + MAIN_DIR + s_PATH)
		LENGTH = int(self.headers["Content-length"])
		VARIABLES = cgi.parse_qs(self.rfile.read(LENGTH),keep_blank_values=1)
		if s_PATH.endswith("/config.html"):
			print("Network settings are updating..")
			self.send_response(204)
			global file_CFG
			file_CFG = open(MAIN_DIR + "/cfg/config.ini","w")
			# NETMODE
			if VARIABLES["fm_netmode"][0]:
				f_ADD_CFG("fm_netmode",VARIABLES["fm_netmode"][0])
			# STATIC IP
			if VARIABLES["fm_staticip"][0]:
				f_ADD_CFG("fm_staticip",VARIABLES["fm_staticip"][0])
			# NETMASK
			if VARIABLES["fm_netmask"][0]:
				f_ADD_CFG("fm_netmask",VARIABLES["fm_netmask"][0])
			# DHCP
			if "fm_dhcp" in VARIABLES:
				f_ADD_CFG("fm_dhcp","1")
				## DHCP START
				if VARIABLES["fm_dhcp_start"][0]:
					f_ADD_CFG("fm_dhcp_start",VARIABLES["fm_dhcp_start"][0])
				## DHCP LIMIT
				if VARIABLES["fm_dhcp_limit"][0]:
					f_ADD_CFG("fm_dhcp_limit",VARIABLES["fm_dhcp_limit"][0])
			else:
				f_ADD_CFG("fm_dhcp","0")
			# DNS
			if "fm_dns" in VARIABLES:
				f_ADD_CFG("fm_dns","1")
				## DNS MODE
				if "fm_dns_mode" in VARIABLES:
					f_ADD_CFG("fm_dns_mode","1")
				else:
					f_ADD_CFG("fm_dns_mode","0")
				## DNS ENTRIES
				if VARIABLES["fm_dns_entries"][0]:
					f = open(MAIN_DIR + "/cfg/hosts.tmp","w")
					f.write(VARIABLES["fm_dns_entries"][0])
					f.close()
					with open(MAIN_DIR + "/cfg/hosts.tmp","r") as src:
						with open(MAIN_DIR + "/cfg/hosts","w") as dest:
							for line in src:
								dest.write("address=/%s" % (line.rstrip("\n")))
					os.remove(MAIN_DIR + "/cfg/hosts.tmp")
			else:
				f_ADD_CFG("fm_dns","0")
			# SSH
			if "fm_ssh" in VARIABLES:
				f_ADD_CFG("fm_ssh","1")
			else:
				f_ADD_CFG("fm_ssh","0")
			# VPN
			if "fm_vpn" in VARIABLES:
				f_ADD_CFG("fm_vpn","1")
				## VPN MODE
				if "fm_vpn_mode" in VARIABLES:
					f_ADD_CFG("fm_vpn_mode","1")
				else:
					f_ADD_CFG("fm_vpn_mode","0")
				## VPN DNS
				if VARIABLES["fm_vpn_dns"][0]:
					f_ADD_CFG("fm_vpn_dns",VARIABLES["fm_vpn_dns"][0])
			else:
				f_ADD_CFG("fm_vpn","0")
			file_CFG.close()
			print("Configuration file created. Applying..")
			f = open(MAIN_DIR + "/CMD_UPDATE","w")
			f.close()
		elif s_PATH.endswith("/command.html"):
			print("Received command, executing..")
			self.send_response(204)
			data = VARIABLES["fm_text"][0]
			f = open(MAIN_DIR + "/CMD_EXECUTE","w")
			f.write(data)
			f.close()
		elif s_PATH.endswith("/payloads.html"):
			print("Payload request")
			self.send_response(204)
			# TCPDUMP
			if "fm_tcpdump" in VARIABLES:
				f = open(MAIN_DIR + "/CMD_PAYLOAD","w")
				f.write("tcpdump" + "\n")
				if VARIABLES["fm_tcpdump_timer"][0]:
					f.write(VARIABLES["fm_tcpdump_timer"][0])
				else:
					f.write(120)
				f.close()
			# CUSTOM PAYLOAD
			elif "fm_custompayload" in VARIABLES:
				if VARIABLES["fm_payload"][0]:
					f = open(MAIN_DIR + "/CMD_PAYLOAD","w")
					f.write(VARIABLES["fm_payload"][0] + "\n")
					if "fm_parallel" in VARIABLES:
						f.write("&")
					f.close()
				else:
					print("Failure: No payload name was found")
			else:
				print("Failure: Nothing was POSTed")
		else:
			self.send_response(401)
			pass

def f_RUN():
	print("Root directory: " + ROOT_DIR)
	print("Main directory: " + MAIN_DIR)
	httpd = TCPServer((s_INTERFACE,n_PORT),c_HANDLER)
	s_ip, _p = httpd.server_address
	print("IP: " + s_ip + ":" + str(_p))
	while b_RUNNING:
		httpd.handle_request()

f_RUN()
