import React from 'react';
import Link from '@docusaurus/Link';
import useBaseUrl from '@docusaurus/useBaseUrl';
import {useThemeConfig} from '@docusaurus/theme-common';

/**
 * Swizzle: replace the default NavbarLogo (which uses ThemedImage → ThemedComponent,
 * rendering two <img> elements during SSR/hydration) with a single inline SVG that
 * reads var(--ifm-color-primary) from CSS.  Because the color mode script sets
 * data-theme on <html> synchronously in <head> before any paint, the CSS variable
 * always resolves to the correct theme color — no dual-image flash possible.
 */
export default function NavbarLogo(): JSX.Element {
    const {
        navbar: {logo},
    } = useThemeConfig();

    const logoLink = useBaseUrl(logo?.href || '/');

    return (
        <Link to={logoLink} className="navbar__brand" aria-label={logo?.alt || 'gfrm logo'}>
            <div className="navbar__logo">
                <img src={useBaseUrl(logo?.src)} alt={logo?.alt} style={{
                    height: '50px',
                    position: 'relative',
                    top: '-10px',
                    left: '15px'
                }}/>
            </div>
        </Link>
    );
}
