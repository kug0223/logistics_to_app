import React from 'react';

const ALfitLogoAssets = () => {
  const colors = {
    primary: '#1976D2',
    secondary: '#2196F3',
    dark: '#0D47A1',
    light: '#E3F2FD'
  };

  // 1. 앱 아이콘 (심플 버전 - 태그라인 없음)
  const AppIcon = ({ size = 1024 }) => (
    <svg width={size} height={size} viewBox="0 0 1024 1024" style={{ background: colors.primary }}>
      <defs>
        <filter id="shadow">
          <feDropShadow dx="0" dy="4" stdDeviation="8" floodOpacity="0.3"/>
        </filter>
      </defs>
      
      {/* 배경 */}
      <rect width="1024" height="1024" fill={colors.primary} rx="180"/>
      
      {/* ALfit 로고 */}
      <text 
        x="512" 
        y="580" 
        fontFamily="Arial, sans-serif" 
        fontSize="280" 
        fontWeight="800" 
        fill="white" 
        textAnchor="middle"
        letterSpacing="8"
        filter="url(#shadow)"
      >
        ALfit
      </text>
      
      {/* 작은 연결점 */}
      <circle cx="420" cy="540" r="18" fill={colors.secondary} opacity="0.8"/>
    </svg>
  );

  // 2. 스플래시 화면용 (태그라인 포함)
  const SplashLogo = ({ size = 800 }) => (
    <svg width={size} height={size * 0.4} viewBox="0 0 1200 480">
      {/* ALfit */}
      <text 
        x="600" 
        y="280" 
        fontFamily="Arial, sans-serif" 
        fontSize="180" 
        fontWeight="800" 
        fill={colors.primary} 
        textAnchor="middle"
        letterSpacing="6"
      >
        ALfit
      </text>
      
      {/* 작은 연결점 */}
      <circle cx="490" cy="250" r="12" fill={colors.secondary}/>
      
      {/* 태그라인 */}
      <text 
        x="600" 
        y="360" 
        fontFamily="Arial, sans-serif" 
        fontSize="42" 
        fontWeight="400" 
        fill={colors.dark} 
        textAnchor="middle"
        letterSpacing="8"
      >
        나에게 딱 맞는 알바
      </text>
    </svg>
  );

  // 3. 다크모드 스플래시
  const SplashLogoDark = ({ size = 800 }) => (
    <svg width={size} height={size * 0.4} viewBox="0 0 1200 480" style={{ background: '#121212' }}>
      {/* ALfit */}
      <text 
        x="600" 
        y="280" 
        fontFamily="Arial, sans-serif" 
        fontSize="180" 
        fontWeight="800" 
        fill="white" 
        textAnchor="middle"
        letterSpacing="6"
      >
        ALfit
      </text>
      
      {/* 작은 연결점 */}
      <circle cx="490" cy="250" r="12" fill={colors.secondary}/>
      
      {/* 태그라인 */}
      <text 
        x="600" 
        y="360" 
        fontFamily="Arial, sans-serif" 
        fontSize="42" 
        fontWeight="400" 
        fill="#E0E0E0" 
        textAnchor="middle"
        letterSpacing="8"
      >
        나에게 딱 맞는 알바
      </text>
    </svg>
  );

  // 4. 단색 버전 (흑백)
  const MonochromeLogo = ({ size = 800, color = '#000000' }) => (
    <svg width={size} height={size * 0.3} viewBox="0 0 1200 360">
      {/* ALfit */}
      <text 
        x="600" 
        y="220" 
        fontFamily="Arial, sans-serif" 
        fontSize="160" 
        fontWeight="800" 
        fill={color} 
        textAnchor="middle"
        letterSpacing="6"
      >
        ALfit
      </text>
      
      {/* 태그라인 */}
      <text 
        x="600" 
        y="300" 
        fontFamily="Arial, sans-serif" 
        fontSize="36" 
        fontWeight="400" 
        fill={color} 
        textAnchor="middle"
        letterSpacing="6"
      >
        나에게 딱 맞는 알바
      </text>
    </svg>
  );

  // 5. 웹 헤더용 (가로형)
  const HeaderLogo = ({ size = 400 }) => (
    <svg width={size} height={size * 0.35} viewBox="0 0 1200 420">
      {/* ALfit */}
      <text 
        x="100" 
        y="240" 
        fontFamily="Arial, sans-serif" 
        fontSize="140" 
        fontWeight="800" 
        fill={colors.primary} 
        letterSpacing="4"
      >
        ALfit
      </text>
      
      {/* 작은 연결점 */}
      <circle cx="280" cy="210" r="10" fill={colors.secondary}/>
      
      {/* 태그라인 */}
      <text 
        x="105" 
        y="310" 
        fontFamily="Arial, sans-serif" 
        fontSize="32" 
        fontWeight="400" 
        fill={colors.dark} 
        letterSpacing="6"
      >
        나에게 딱 맞는 알바
      </text>
    </svg>
  );

  const downloadSVG = (svgElement, filename) => {
    const svgData = new XMLSerializer().serializeToString(svgElement);
    const blob = new Blob([svgData], { type: 'image/svg+xml' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    link.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div style={{ 
      padding: '40px', 
      maxWidth: '1400px', 
      margin: '0 auto',
      fontFamily: '-apple-system, system-ui, sans-serif',
      background: '#fafafa',
      minHeight: '100vh'
    }}>
      <h1 style={{ textAlign: 'center', marginBottom: '10px', fontSize: '42px', fontWeight: '800' }}>
        ALfit 로고 파일 생성 완료! 🎉
      </h1>
      <p style={{ textAlign: 'center', color: '#666', marginBottom: '50px', fontSize: '18px' }}>
        앱 아이콘, 스플래시 화면, 다양한 크기 - 모두 준비 완료
      </p>

      {/* 파일 세트 */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: '30px' }}>
        
        {/* 1. 앱 아이콘 */}
        <div style={{ background: 'white', padding: '40px', borderRadius: '20px', boxShadow: '0 4px 12px rgba(0,0,0,0.08)' }}>
          <h2 style={{ marginBottom: '20px', fontSize: '24px', fontWeight: '700' }}>
            📱 1. 앱 아이콘 (1024x1024)
          </h2>
          <div style={{ display: 'flex', gap: '30px', alignItems: 'center', flexWrap: 'wrap' }}>
            <div style={{ 
              background: '#f5f5f5', 
              padding: '30px', 
              borderRadius: '16px',
              display: 'flex',
              justifyContent: 'center',
              alignItems: 'center'
            }}>
              <div style={{ 
                width: '200px', 
                height: '200px',
                borderRadius: '40px',
                overflow: 'hidden',
                boxShadow: '0 8px 24px rgba(0,0,0,0.15)'
              }}>
                <AppIcon size={200} />
              </div>
            </div>
            <div style={{ flex: 1, minWidth: '300px' }}>
              <h3 style={{ fontSize: '18px', fontWeight: '600', marginBottom: '15px' }}>사용처</h3>
              <ul style={{ listStyle: 'none', padding: 0, fontSize: '15px', color: '#666' }}>
                <li style={{ marginBottom: '10px' }}>✓ iOS App Store (1024x1024)</li>
                <li style={{ marginBottom: '10px' }}>✓ Google Play Store</li>
                <li style={{ marginBottom: '10px' }}>✓ Flutter 앱 아이콘</li>
                <li style={{ marginBottom: '10px' }}>✓ 푸시 알림 아이콘</li>
              </ul>
              <button
                onClick={(e) => {
                  const svg = e.currentTarget.parentElement.parentElement.querySelector('svg');
                  downloadSVG(svg, 'ALfit_app_icon_1024.svg');
                }}
                style={{
                  marginTop: '20px',
                  padding: '12px 24px',
                  background: colors.primary,
                  color: 'white',
                  border: 'none',
                  borderRadius: '10px',
                  cursor: 'pointer',
                  fontWeight: '600',
                  fontSize: '15px'
                }}
              >
                SVG 다운로드
              </button>
            </div>
          </div>
        </div>

        {/* 2. 스플래시 화면 (라이트) */}
        <div style={{ background: 'white', padding: '40px', borderRadius: '20px', boxShadow: '0 4px 12px rgba(0,0,0,0.08)' }}>
          <h2 style={{ marginBottom: '20px', fontSize: '24px', fontWeight: '700' }}>
            🌅 2. 스플래시 화면 (라이트 모드)
          </h2>
          <div style={{ 
            background: 'white', 
            padding: '60px', 
            borderRadius: '16px',
            border: '1px solid #e0e0e0',
            marginBottom: '20px'
          }}>
            <SplashLogo size={600} />
          </div>
          <button
            onClick={(e) => {
              const svg = e.currentTarget.parentElement.querySelector('svg');
              downloadSVG(svg, 'ALfit_splash_light.svg');
            }}
            style={{
              padding: '12px 24px',
              background: colors.primary,
              color: 'white',
              border: 'none',
              borderRadius: '10px',
              cursor: 'pointer',
              fontWeight: '600',
              fontSize: '15px'
            }}
          >
            SVG 다운로드
          </button>
        </div>

        {/* 3. 스플래시 화면 (다크) */}
        <div style={{ background: 'white', padding: '40px', borderRadius: '20px', boxShadow: '0 4px 12px rgba(0,0,0,0.08)' }}>
          <h2 style={{ marginBottom: '20px', fontSize: '24px', fontWeight: '700' }}>
            🌙 3. 스플래시 화면 (다크 모드)
          </h2>
          <div style={{ 
            background: '#121212', 
            padding: '60px', 
            borderRadius: '16px',
            marginBottom: '20px'
          }}>
            <SplashLogoDark size={600} />
          </div>
          <button
            onClick={(e) => {
              const svg = e.currentTarget.parentElement.querySelector('svg');
              downloadSVG(svg, 'ALfit_splash_dark.svg');
            }}
            style={{
              padding: '12px 24px',
              background: '#1a1a1a',
              color: 'white',
              border: 'none',
              borderRadius: '10px',
              cursor: 'pointer',
              fontWeight: '600',
              fontSize: '15px'
            }}
          >
            SVG 다운로드
          </button>
        </div>

        {/* 4. 단색 버전 */}
        <div style={{ background: 'white', padding: '40px', borderRadius: '20px', boxShadow: '0 4px 12px rgba(0,0,0,0.08)' }}>
          <h2 style={{ marginBottom: '20px', fontSize: '24px', fontWeight: '700' }}>
            ⚫ 4. 단색 버전 (흑백)
          </h2>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px', marginBottom: '20px' }}>
            <div style={{ background: 'white', padding: '40px', borderRadius: '16px', border: '1px solid #e0e0e0' }}>
              <h3 style={{ fontSize: '16px', marginBottom: '20px', color: '#666' }}>검은색 버전</h3>
              <MonochromeLogo size={400} color="#000000" />
            </div>
            <div style={{ background: '#1a1a1a', padding: '40px', borderRadius: '16px' }}>
              <h3 style={{ fontSize: '16px', marginBottom: '20px', color: '#999' }}>흰색 버전</h3>
              <MonochromeLogo size={400} color="#FFFFFF" />
            </div>
          </div>
          <div style={{ display: 'flex', gap: '10px' }}>
            <button
              onClick={(e) => {
                const svg = e.currentTarget.parentElement.parentElement.querySelectorAll('svg')[0];
                downloadSVG(svg, 'ALfit_monochrome_black.svg');
              }}
              style={{
                padding: '12px 24px',
                background: '#000',
                color: 'white',
                border: 'none',
                borderRadius: '10px',
                cursor: 'pointer',
                fontWeight: '600',
                fontSize: '15px'
              }}
            >
              검은색 다운로드
            </button>
            <button
              onClick={(e) => {
                const svg = e.currentTarget.parentElement.parentElement.querySelectorAll('svg')[1];
                downloadSVG(svg, 'ALfit_monochrome_white.svg');
              }}
              style={{
                padding: '12px 24px',
                background: '#666',
                color: 'white',
                border: 'none',
                borderRadius: '10px',
                cursor: 'pointer',
                fontWeight: '600',
                fontSize: '15px'
              }}
            >
              흰색 다운로드
            </button>
          </div>
        </div>

        {/* 5. 헤더용 */}
        <div style={{ background: 'white', padding: '40px', borderRadius: '20px', boxShadow: '0 4px 12px rgba(0,0,0,0.08)' }}>
          <h2 style={{ marginBottom: '20px', fontSize: '24px', fontWeight: '700' }}>
            💻 5. 웹 헤더용 (가로형)
          </h2>
          <div style={{ 
            background: 'white', 
            padding: '40px', 
            borderRadius: '16px',
            border: '1px solid #e0e0e0',
            marginBottom: '20px'
          }}>
            <HeaderLogo size={400} />
          </div>
          <button
            onClick={(e) => {
              const svg = e.currentTarget.parentElement.querySelector('svg');
              downloadSVG(svg, 'ALfit_header_logo.svg');
            }}
            style={{
              padding: '12px 24px',
              background: colors.primary,
              color: 'white',
              border: 'none',
              borderRadius: '10px',
              cursor: 'pointer',
              fontWeight: '600',
              fontSize: '15px'
            }}
          >
            SVG 다운로드
          </button>
        </div>

      </div>

      {/* Flutter 적용 가이드 */}
      <div style={{
        marginTop: '50px',
        background: `linear-gradient(135deg, ${colors.primary}, ${colors.secondary})`,
        padding: '40px',
        borderRadius: '20px',
        color: 'white'
      }}>
        <h2 style={{ fontSize: '28px', fontWeight: '700', marginBottom: '20px' }}>
          📱 Flutter 앱에 적용하기
        </h2>
        <div style={{ 
          background: 'rgba(255,255,255,0.1)', 
          padding: '30px', 
          borderRadius: '16px',
          fontFamily: 'monospace',
          fontSize: '14px',
          lineHeight: '1.8'
        }}>
          <p style={{ marginBottom: '20px', fontFamily: 'Arial', fontSize: '16px' }}>
            <strong>1단계: 파일 저장</strong>
          </p>
          <code style={{ display: 'block', whiteSpace: 'pre', marginBottom: '30px' }}>
{`assets/images/logo_splash_light.svg
assets/images/logo_splash_dark.svg
assets/images/app_icon.png (1024x1024)`}
          </code>

          <p style={{ marginBottom: '20px', fontFamily: 'Arial', fontSize: '16px' }}>
            <strong>2단계: pubspec.yaml 설정</strong>
          </p>
          <code style={{ display: 'block', whiteSpace: 'pre', marginBottom: '30px' }}>
{`flutter:
  assets:
    - assets/images/logo_splash_light.svg
    - assets/images/logo_splash_dark.svg`}
          </code>

          <p style={{ marginBottom: '20px', fontFamily: 'Arial', fontSize: '16px' }}>
            <strong>3단계: 스플래시 화면 코드 (아래에서 제공)</strong>
          </p>
        </div>
      </div>
    </div>
  );
};

export default ALfitLogoAssets;
