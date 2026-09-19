'use strict';
'require view';

/* The Wi-Fi radio, and anything else on the x86 side, is a second OpenWrt
 * reached through the PCIe link (ntb0, 192.168.1.2). Its own LuCI has the
 * wireless and USB pages. */
return view.extend({
	render: function() {
		var host = '192.168.1.2', base = 'http://' + host + '/cgi-bin/luci/admin/';

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', _('Wi-Fi / x86 module')),
			E('div', { 'class': 'cbi-map-descr' },
				_('The Wi-Fi card lives on the x86 module of this appliance, which runs its own OpenWrt and is connected to this router over PCIe (ntb0). Its web interface is at %s.').format(host)),
			E('div', { 'class': 'cbi-section' }, [
				E('a', { 'class': 'cbi-button cbi-button-action important', 'href': base + 'network/wireless', 'target': '_blank' }, _('Wi-Fi settings')),
				' ',
				E('a', { 'class': 'cbi-button', 'href': base + 'status/overview', 'target': '_blank' }, _('x86 module status'))
			])
		]);
	},
	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
