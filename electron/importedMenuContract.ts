const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("imported_menu_contract");

export type ImportedMenuValue = string | number | boolean;
export type ImportedMenuOption = string | { label: string; value: ImportedMenuValue };
export interface ImportedMenuItem {
  id?: string;
  type: string;
  label?: string;
  value?: ImportedMenuValue | { percent: number; text?: string };
  default?: ImportedMenuValue | { percent: number; text?: string };
  options?: ImportedMenuOption[];
  min?: number;
  max?: number;
  step?: number;
  variant?: string;
  placeholder?: string;
  disabled?: boolean;
  enabled?: boolean;
  readOnly?: boolean;
  items?: ImportedMenuItem[];
  confirm?: { title: string; message: string; confirmLabel?: string; cancelLabel?: string };
}
export interface ImportedMenuSection { id: string; title: string; tab?: string; items: ImportedMenuItem[] }
export interface ImportedMenuSnapshot {
  schema: 1;
  sessionId: string;
  revision: number;
  heartbeat?: number;
  pendingFiniteTasks?: number;
  buildId?: string;
  ready: boolean;
  message?: string;
  sections: ImportedMenuSection[];
  operation?: { id: string; status: "queued" | "running" | "awaiting-confirmation" | "completed" | "failed"; message?: string };
  confirmation?: { token: string; title: string; message: string; confirmLabel?: string; cancelLabel?: string };
  messages?: string[];
  // Present only in the final snapshot of a clean quit ("quit"). Its absence after the
  // process has gone is how an unclean exit is recognised (see steamRecovery.ts).
  shutdown?: string;
}
export interface ImportedMenuDispatchRequest {
  sessionId: string;
  action: "invoke" | "set" | "confirm" | "refresh" | "close";
  sectionId?: string;
  itemId?: string;
  value?: ImportedMenuValue;
  confirmationToken?: string;
  confirmed?: boolean;
}
export interface ImportedMenuTransport {
  state(): Promise<ImportedMenuSnapshot>;
  dispatch(request: ImportedMenuDispatchRequest): Promise<{ accepted: boolean; message: string; operationId?: string }>;
}

