import OpenGLES
import QuartzCore
import UIKit

/// Hosts the EAGL drawable that will become the game's back buffer.
///
/// It already brings up an OpenGL ES 3 context and presents a frame every
/// CADisplayLink tick, so the renderer plumbing (context, drawable, viewport,
/// lifecycle) is proven before the core is linked.
final class GameGLView: UIView {
    override class var layerClass: AnyClass { CAEAGLLayer.self }

    private var context: EAGLContext?
    private var framebuffer: GLuint = 0
    private var colorRenderbuffer: GLuint = 0
    private var depthRenderbuffer: GLuint = 0
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var wantsFrames = false

    private(set) var rendererInfo = "OpenGL ES indisponivel"
    private(set) var isReady = false

    /// Called once per frame, before the frame is presented.
    var onFrame: ((Double) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopRendering()
        destroyBuffers()
    }

    private func commonInit() {
        backgroundColor = .black
        isOpaque = true
        isUserInteractionEnabled = false

        guard let drawable = layer as? CAEAGLLayer else { return }
        drawable.isOpaque = true
        drawable.contentsScale = UIScreen.main.scale
        drawable.drawableProperties = [
            kEAGLDrawablePropertyRetainedBacking: false,
            kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8
        ]

        guard let created = EAGLContext(api: .openGLES3) else { return }
        context = created
        EAGLContext.setCurrent(created)

        if let version = glGetString(GLenum(GL_VERSION)) {
            rendererInfo = String(
                cString: UnsafeRawPointer(version).assumingMemoryBound(to: CChar.self)
            )
        } else {
            rendererInfo = "OpenGL ES 3 (sem versao)"
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(willResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildBuffers()
    }

    func startRendering() {
        wantsFrames = true
        guard displayLink == nil else { return }
        lastTimestamp = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopRendering() {
        wantsFrames = false
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func willResignActive() {
        displayLink?.isPaused = true
    }

    @objc private func didBecomeActive() {
        guard wantsFrames else { return }
        lastTimestamp = CACurrentMediaTime()
        displayLink?.isPaused = false
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        var delta = now - lastTimestamp
        lastTimestamp = now
        if delta < 0 { delta = 0 }
        if delta > 0.1 { delta = 0.1 }
        render(delta)
    }

    private func rebuildBuffers() {
        guard let ctx = context, bounds.width > 0, bounds.height > 0 else { return }
        guard let drawable = layer as? CAEAGLLayer else { return }

        EAGLContext.setCurrent(ctx)
        destroyBuffers()

        let scale = max(drawable.contentsScale, 1)
        let width = GLsizei(max(1, Int(bounds.width * scale)))
        let height = GLsizei(max(1, Int(bounds.height * scale)))

        glGenFramebuffers(1, &framebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)

        glGenRenderbuffers(1, &colorRenderbuffer)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderbuffer)
        guard ctx.renderbufferStorage(Int(GL_RENDERBUFFER), from: drawable) else {
            isReady = false
            return
        }
        glFramebufferRenderbuffer(
            GLenum(GL_FRAMEBUFFER),
            GLenum(GL_COLOR_ATTACHMENT0),
            GLenum(GL_RENDERBUFFER),
            colorRenderbuffer
        )

        glGenRenderbuffers(1, &depthRenderbuffer)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), depthRenderbuffer)
        glRenderbufferStorage(GLenum(GL_RENDERBUFFER), GLenum(GL_DEPTH_COMPONENT16), width, height)
        glFramebufferRenderbuffer(
            GLenum(GL_FRAMEBUFFER),
            GLenum(GL_DEPTH_ATTACHMENT),
            GLenum(GL_RENDERBUFFER),
            depthRenderbuffer
        )

        isReady = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) == GLenum(GL_FRAMEBUFFER_COMPLETE)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderbuffer)
        re4_core_set_viewport(Int32(width), Int32(height))
    }

    private func destroyBuffers() {
        guard let ctx = context else { return }
        EAGLContext.setCurrent(ctx)
        if depthRenderbuffer != 0 {
            glDeleteRenderbuffers(1, &depthRenderbuffer)
            depthRenderbuffer = 0
        }
        if colorRenderbuffer != 0 {
            glDeleteRenderbuffers(1, &colorRenderbuffer)
            colorRenderbuffer = 0
        }
        if framebuffer != 0 {
            glDeleteFramebuffers(1, &framebuffer)
            framebuffer = 0
        }
        isReady = false
    }

    private func render(_ delta: Double) {
        guard let ctx = context, isReady, framebuffer != 0 else { return }
        EAGLContext.setCurrent(ctx)

        onFrame?(delta)

        let scale = max(layer.contentsScale, 1)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
        glViewport(
            0,
            0,
            GLsizei(max(1, Int(bounds.width * scale))),
            GLsizei(max(1, Int(bounds.height * scale)))
        )

        // A slow pulse proves the frame loop is alive without shipping any art.
        let phase = Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 8.0) / 8.0)
        glClearColor(0.020 + 0.030 * phase, 0.030, 0.055 + 0.040 * phase, 1.0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))

        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderbuffer)
        _ = ctx.presentRenderbuffer(Int(GL_RENDERBUFFER))
    }
}
