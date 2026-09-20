import "@fontsource/cinzel/400.css";
import "@fontsource/cinzel/500.css";
import "@fontsource/cinzel/600.css";
import "@fontsource/cormorant-garamond/400.css";
import "@fontsource/cormorant-garamond/500.css";
import "@fontsource/cormorant-garamond/600.css";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import "./styles.css";
import "./ReferenceTheme.css";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("renderer_entry");

const rootElement = document.getElementById("root");
if (!rootElement) throw new Error("The Blood of Dawnwalker application root is missing.");

createRoot(rootElement).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
