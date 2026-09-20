const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("reminder_toast");

function escapeXml(value: string): string {
  return value.replace(/[&<>"']/g, character =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&apos;" })[character] ?? character);
}

function fileUri(path: string): string {
  return `file:///${path.split(String.fromCharCode(92)).join("/").replace(/^[/]+/, "")}`;
}

/**
 * ToastGeneric XML for the objective reminder. Windows owns the notification frame,
 * but the app chooses the logo, both text lines and the attribution,
 * which is what makes this read as the menu's own alert rather than a generic toast.
 */
export function buildReminderToastXml(options: Readonly<{
  questTitle: string; objective: string; logoPath: string;
}>): string {
  return "<toast activationType=\"protocol\" launch=\"\" scenario=\"reminder\">"
    + "<visual><binding template=\"ToastGeneric\">"
    + `<image placement="appLogoOverride" hint-crop="default" src="${escapeXml(fileUri(options.logoPath))}"/>`
    + `<text hint-maxLines="1">${escapeXml(options.questTitle)}</text>`
    + `<text>${escapeXml(options.objective)}</text>`
    + "<text placement=\"attribution\">Blood of Dawnwalker Mod Menu</text>"
    + "</binding></visual>"
    + "<audio src=\"ms-winsoundevent:Notification.Reminder\"/>"
    + "</toast>";
}
