import MessageKit

class ChatViewAttachmentCell: MessageContentCell {

    open var imageView: UIImageView = {
        let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    public lazy var titleLabel: UILabel = {
        let titleLabel = UILabel(frame: CGRect.zero)
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = UIColor.mnz_label()
        titleLabel.lineBreakMode = .byTruncatingMiddle
        return titleLabel
    }()

    public lazy var detailLabel: UILabel = {
        let detailLabel = UILabel(frame: CGRect.zero)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = UIColor.mnz_subtitles(for: UIScreen.main.traitCollection)
        detailLabel.lineBreakMode = .byTruncatingMiddle
        return detailLabel
    }()

    // MARK: - Methods

    /// Responsible for setting up the constraints of the cell's subviews.
    open func setupConstraints() {
        imageView.autoSetDimensions(to: CGSize(width: 40, height: 40))
        imageView.autoAlignAxis(toSuperviewAxis: .horizontal)
        imageView.autoPinEdge(toSuperviewEdge: .leading, withInset: 10)

        titleLabel.autoPinEdge(.leading, to: .trailing, of: imageView, withOffset: 10)
        titleLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 10)
        titleLabel.autoSetDimension(.height, toSize: 18)
        titleLabel.autoAlignAxis(.horizontal, toSameAxisOf: messageContainerView, withOffset: -8)

        detailLabel.autoPinEdge(.leading, to: .trailing, of: imageView, withOffset: 10)
        detailLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 10)
        detailLabel.autoSetDimension(.height, toSize: 18)
        detailLabel.autoAlignAxis(.horizontal, toSameAxisOf: messageContainerView, withOffset: 8)
    }

    open override func setupSubviews() {
        super.setupSubviews()
        messageContainerView.addSubview(imageView)
        messageContainerView.addSubview(titleLabel)
        messageContainerView.addSubview(detailLabel)
        setupConstraints()
    }
    
    var attachmentViewModel: ChatViewAttachmentCellViewModel! {
        didSet {
            configureUI()
        }
    }
    
    private func configureUI() {
        titleLabel.text = attachmentViewModel.title
        detailLabel.text = attachmentViewModel.subtitle
        attachmentViewModel.set(imageView: imageView)
    }
    
    override func configure(with message: MessageType, at indexPath: IndexPath, and messagesCollectionView: MessagesCollectionView) {
        super.configure(with: message, at: indexPath, and: messagesCollectionView)
        
        guard let chatMessage = message as? ChatMessage else {
            return
        }
        
        self.attachmentViewModel = ChatViewAttachmentCellViewModel(chatMessage: chatMessage)
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        guard #available(iOS 13, *) else {
            return
        }
        titleLabel.textColor = UIColor.mnz_label()
        detailLabel.textColor = UIColor.mnz_subtitles(for: UIScreen.main.traitCollection)
    }
    
    func sizeThatFits() -> CGSize {
        titleLabel.sizeToFit()
        detailLabel.sizeToFit()
        
        let width = 75 + max(titleLabel.bounds.width, detailLabel.bounds.width)
        return CGSize(width: width, height: 60)
    }
}

open class ChatViewAttachmentCellCalculator: MessageSizeCalculator {
    
    let chatViewAttachmentCell = ChatViewAttachmentCell()
    
    public override init(layout: MessagesCollectionViewFlowLayout? = nil) {
        super.init(layout: layout)
        configureAccessoryView()
    }

    open override func messageContainerSize(for message: MessageType) -> CGSize {
       guard let chatMessage = message as? ChatMessage else {
            fatalError("ChatViewAttachmentCellCalculator: wrong type message passed.")
        }
        
        let maxWidth = messageContainerMaxWidth(for: message)
        
        chatViewAttachmentCell.attachmentViewModel = ChatViewAttachmentCellViewModel(chatMessage: chatMessage)
        let size = chatViewAttachmentCell.sizeThatFits()
        
        return CGSize(width: min(size.width, maxWidth), height: size.height)
    }
}
