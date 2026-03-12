import React from 'react';
import Link from '@docusaurus/Link';
import useBaseUrl from '@docusaurus/useBaseUrl';
import { useThemeConfig } from '@docusaurus/theme-common';

/**
 * Swizzle: replace the default NavbarLogo (which uses ThemedImage → ThemedComponent,
 * rendering two <img> elements during SSR/hydration) with a single inline SVG that
 * reads var(--ifm-color-primary) from CSS.  Because the color mode script sets
 * data-theme on <html> synchronously in <head> before any paint, the CSS variable
 * always resolves to the correct theme color — no dual-image flash possible.
 */
export default function NavbarLogo(): JSX.Element {
  const {
    navbar: { logo },
  } = useThemeConfig();

  const logoLink = useBaseUrl(logo?.href || '/');

  return (
    <Link to={logoLink} className="navbar__brand" aria-label={logo?.alt || 'gfrm logo'}>
      <div className="navbar__logo">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 105 48"
          height={logo?.height ?? 28}
          aria-hidden="true"
          focusable="false"
        >
          <g
            fill="none"
            stroke="var(--ifm-color-primary)"
            strokeWidth="2.5"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            {/* Left forge node */}
            <rect x="8" y="22" width="8" height="8" rx="2" />
            {/* Right forge node */}
            <rect x="28" y="10" width="8" height="8" rx="2" />
            {/* Git branch point */}
            <circle cx="20" cy="24" r="2.2" fill="var(--ifm-color-primary)" stroke="none" />
            {/* Branch lines */}
            <path d="M16 26H20" />
            <path d="M20 24V16" />
            <path d="M20 16H28" />
            {/* Migration arrow */}
            <path d="M16 26H27" />
            <path d="M24 23L27 26L24 29" />
          </g>
          <text
            x="40"
            y="32"
            fontFamily="Inter, Segoe UI, Arial, sans-serif"
            fontSize="24"
            fontWeight="700"
            fill="var(--ifm-color-primary)"
            letterSpacing="0.5"
          >
            gfrm
          </text>
        </svg>
      </div>
    </Link>
  );
}
