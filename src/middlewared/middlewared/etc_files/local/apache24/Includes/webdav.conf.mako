<%
    import os
    import shutil
    import stat

    from contextlib import suppress

    from middlewared.plugins.webdav import WEBDAV_USER

    webdav_uid = middleware.call_sync('user.get_builtin_user_id', WEBDAV_USER)
    webdav_gid = middleware.call_sync('group.get_builtin_group_id', WEBDAV_USER)

    # Check to see if there is a webdav lock database directory, if not create
    # one. Take care of necessary permissions whilst creating it!
    oscmd = '/etc/apache2/var'
    with suppress(FileExistsError):
        os.mkdir(oscmd, 0o774)

    if stat.S_IMODE(os.stat(oscmd).st_mode) != 0o774:
        os.chmod(oscmd, 0o774)

    shutil.chown(oscmd, user=webdav_uid, group=webdav_gid)

    webdav_config = render_ctx['webdav.config']
    auth_type = webdav_config['htauth'].lower()
    web_shares = render_ctx['sharing.webdav.query']
%>\
Listen ${webdav_config['tcpport']}
	<VirtualHost *:${webdav_config['tcpport']}>
		DavLockDB "/etc/apache2/var/DavLock"

		<Directory />
% if auth_type != 'none':
			AuthType ${auth_type}
			AuthName webdav
			AuthUserFile "/etc/apache2/webdavht${auth_type}"
	% if auth_type == 'digest':
			AuthDigestProvider file
	% endif
			Require valid-user

% endif
			Dav On
			IndexOptions Charset=utf-8
			AddDefaultCharset UTF-8
			AllowOverride None
			Order allow,deny
			Allow from all
			Options Indexes FollowSymLinks
		</Directory>

% for share in web_shares:
	<%
		if share['locked']:
			middleware.logger.debug(
			    'Skipping generation of %r webdav share as underlying resource is locked', share['name']
			)
			middleware.call_sync('sharing.webdav.generate_locked_alert', share['id'])
			continue
	%>\
		Alias /${share['name']} "${share['path']}"
		<Directory "${share['path']}" >
		</Directory>
	% if share['ro']:
		<Location "/${share['name']}" >
			AllowMethods GET OPTIONS PROPFIND
		</Location>
	% endif

% endfor
		# The following directives disable redirects on non-GET requests for
		# a directory that does not include the trailing slash.  This fixes a
		# problem with several clients that do not appropriately handle
		# redirects for folders with DAV methods.
		BrowserMatch "Microsoft Data Access Internet Publishing Provider" redirect-carefully
		BrowserMatch "MS FrontPage" redirect-carefully
		BrowserMatch "^WebDrive" redirect-carefully
		BrowserMatch "^WebDAVFS/1.[01234]" redirect-carefully
		BrowserMatch "^gnome-vfs/1.0" redirect-carefully
		BrowserMatch "^XML Spy" redirect-carefully
		BrowserMatch "^Dreamweaver-WebDAV-SCM1" redirect-carefully
		BrowserMatch " Konqueror/4" redirect-carefully
		RequestReadTimeout handshake=0 header=20-40,MinRate=500 body=20,MinRate=500
	</VirtualHost>
