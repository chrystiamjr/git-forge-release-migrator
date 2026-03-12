import React from 'react';
import LocaleSwitcher from '../components/LocaleSwitcher';

// Swizzle Root to inject a floating locale switcher on mobile.
// On desktop (≥997px) the localeDropdown in the navbar is sufficient;
// the floating button is hidden via CSS (custom.css .gfrm-locale-float).
export default function Root({ children }: { children: React.ReactNode }): JSX.Element {
  return (
    <>
      {children}
      <div className="gfrm-locale-float">
        <LocaleSwitcher variant="floating" />
      </div>
    </>
  );
}
