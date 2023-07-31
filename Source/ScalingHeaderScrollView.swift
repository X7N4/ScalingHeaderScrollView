//
//  ScalingHeaderScrollView.swift
//  ScalingHeaderScrollView
//
//  Created by Alisa Mylnikova on 16/09/2021.
//  Copyright © 2021 Exyte. All rights reserved.
//

import SwiftUI
import SwiftUIIntrospect

public struct ScalingHeaderScrollView<Header: View, Content: View>: View {
    /// Content on the top, which will be collapsed
    public var header: Header

    /// Content on the bottom
    public var content: Content

    /// Should the progress view be showing or not
    @State private var isSpinning: Bool = false

    /// UIKit's UIScrollView
    @State private var uiScrollView: UIScrollView?

    /// UIScrollView delegate, needed for calling didPullToRefresh or didEndDragging
    @StateObject private var scrollViewDelegate = ScalingHeaderScrollViewDelegate()

    /// ScrollView's content frame, needed for calculation of frame changing
    @StateObject private var contentFrame = ViewFrame()

    /// Interpolation from 0 to 1 of current collapse progress
    @Binding private var progress: CGFloat

    /// Current ScrollView offset
    @Binding private var scrollOffset: CGFloat

    /// Scale of header based on pull to refresh gesture
    @Binding private var pullToRefreshScale: CGFloat

    /// Automatically sets to true, if pull to refresh is triggered. Manually set to false to hide loading indicator.
    @Binding private var isLoading: Bool

    /// Set to true to immediately scroll to top
    @Binding private var scrollToTop: Bool

    /// Called once pull to refresh is triggered
    private var didPullToRefresh: (() -> Void)?

    /// Height for uncollapsed state
    private var maxHeight: CGFloat = 350.0

    /// Height for collapsed state
    private var minHeight: CGFloat = 150.0

    /// Allow collapsing while scrolling up
    private var allowsHeaderCollapseFlag: Bool = false

    /// Allow enlarging while pulling down
    private var allowsHeaderGrowthFlag: Bool = false

    /// Allow force snap to closest position after lifting the finger, i.e. forbid to be left in unfinished state
    private var allowsHeaderSnapFlag: Bool = false

    /// Shows or hides the indicator for the scrollView
    private var showsIndicators: Bool = true

    /// Private computed properties

    private var noPullToRefresh: Bool {
        didPullToRefresh == nil
    }

    private var contentOffset: CGFloat {
        maxHeight
    }

    private var progressViewOffset: CGFloat {
        isLoading ? maxHeight + 24.0 : maxHeight
    }

    /// height for header: reduced if reducing is allowed, or fixed if not
    private var headerHeight: CGFloat {
        allowsHeaderCollapseFlag ? getHeightForHeaderView() : maxHeight
    }

    /// Scaling for header: to enlarge while pulling down
    private var headerScaleOnPullDown: CGFloat {
        allowsHeaderGrowthFlag ? max(1.0, getHeightForHeaderView() / maxHeight * 0.9) : 1.0
    }

    private var needToShowProgressView: Bool {
        !noPullToRefresh && (isLoading || isSpinning)
    }

    // MARK: - Init

    public init(@ViewBuilder header: @escaping () -> Header, @ViewBuilder content: @escaping () -> Content) {
        self.header = header()
        self.content = content()
        _progress = .constant(0)
        _scrollOffset = .constant(0)
        _isLoading = .constant(false)
        _scrollToTop = .constant(false)
        _pullToRefreshScale = .constant(1)
    }

    // MARK: - Body builder

    public var body: some View {
        ScrollView(showsIndicators: showsIndicators) {
            content
                .offset(y: contentOffset)
                .frameGetter($contentFrame.frame)
                .onChange(of: contentFrame.frame) { frame in
                    isSpinning = frame.minY > 20.0
                }
                .onChange(of: scrollToTop) { value in
                    if value {
                        scrollToTop = false
                        setScrollPositionToTop()
                    }
                }

            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    header
                        .frame(height: headerHeight)
                        .clipped()
                        .offset(y: getOffsetForHeader())
                        .allowsHitTesting(true)
                        .scaleEffect(headerScaleOnPullDown)

                    if needToShowProgressView {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(width: UIScreen.main.bounds.width, height: headerHeight)
                            .scaleEffect(1.25)
                            .allowsHitTesting(false)
                            .offset(y: getOffsetForHeader() + 10)
                    }
                }
                .offset(y: getGeometryReaderVsScrollView(geometry))
            }
            .background(Color.clear)
            .frame(height: maxHeight)
            .offset(y: -(contentFrame.startingRect?.maxY ?? UIScreen.main.bounds.height))
        }
        .introspect(.scrollView, on: .iOS(.v16, .v17)) { scrollView in
            configure(scrollView: scrollView)
        }
    }

    // MARK: - Private configure

    private func configure(scrollView: UIScrollView) {
        scrollView.delegate = scrollViewDelegate
        if let didPullToRefresh = didPullToRefresh {
            scrollViewDelegate.didPullToRefresh = {
                withAnimation { isLoading = true }
                didPullToRefresh()
            }
        }
        scrollViewDelegate.didScroll = {
            DispatchQueue.main.async {
                progress = getCollapseProgress()
                scrollOffset = getScrollOffset()
                pullToRefreshScale = max(1.0, getHeightForHeaderView() / maxHeight * 0.9)
            }
        }

        scrollViewDelegate.didEndDragging = {
            isSpinning = false
            if allowsHeaderSnapFlag {
                snapScrollPosition()
            }
        }
        DispatchQueue.main.async {
            if uiScrollView != scrollView {
                uiScrollView = scrollView
            }
        }
    }

    // MARK: - Private actions

    private func setScrollPositionToTop() {
        guard var contentOffset = uiScrollView?.contentOffset, contentOffset.y > 0 else { return }
        contentOffset.y = maxHeight - minHeight
        uiScrollView?.setContentOffset(contentOffset, animated: true)
    }

    private func snapScrollPosition() {
        guard var contentOffset = uiScrollView?.contentOffset else { return }
        let extraSpace: CGFloat = maxHeight - minHeight
        contentOffset.y = contentOffset.y < extraSpace / 2 ? 0 : max(extraSpace, contentOffset.y)
        uiScrollView?.setContentOffset(contentOffset, animated: true)
    }

    // MARK: - Private getters for heights and offsets

    private func getScrollOffset() -> CGFloat {
        -(uiScrollView?.contentOffset.y ?? 0)
    }

    private func getGeometryReaderVsScrollView(_ geometry: GeometryProxy) -> CGFloat {
        getScrollOffset() - geometry.frame(in: .global).minY
    }

    private func getOffsetForHeader() -> CGFloat {
        let offset = getScrollOffset()
        let extraSpace = maxHeight - minHeight

        if offset < -extraSpace {
            let imageOffset = abs(min(-extraSpace, offset))
            return allowsHeaderCollapseFlag ? imageOffset : (minHeight - maxHeight) - offset
        } else if offset > 0 {
            return -offset
        }
        return maxHeight - headerHeight
    }

    private func getHeightForHeaderView() -> CGFloat {
        let offset = getScrollOffset()
        return max(minHeight, maxHeight + offset)
    }

    private func getCollapseProgress() -> CGFloat {
        1 - min(max((getHeightForHeaderView() - minHeight) / (maxHeight - minHeight), 0), 1)
    }

    private func getHeightForLoadingView() -> CGFloat {
        max(0, getScrollOffset())
    }
}

// MARK: - Modifiers

public extension ScalingHeaderScrollView {
    /// Passes current collapse progress value into progress binding
    func collapseProgress(_ progress: Binding<CGFloat>) -> ScalingHeaderScrollView {
        var scalingHeaderScrollView = self
        scalingHeaderScrollView._progress = progress
        return scalingHeaderScrollView
    }

    /// Passes current scrollOffset  into scrollOfset binding
    func scrollOffset(_ scrollOffset: Binding<CGFloat>) -> ScalingHeaderScrollView {
        var scalingHeaderScrollView = self
        scalingHeaderScrollView._scrollOffset = scrollOffset
        return scalingHeaderScrollView
    }

    func pullToRefreshScale(_ pullToRefreshScale: Binding<CGFloat>) -> ScalingHeaderScrollView {
        var scalingHeaderScrollView = self
        scalingHeaderScrollView._pullToRefreshScale = pullToRefreshScale
        return scalingHeaderScrollView
    }

    /// Allows to set up callback and `isLoading` state for pull-to-refresh action
    func pullToRefresh(isLoading: Binding<Bool>, perform: @escaping () -> Void) -> ScalingHeaderScrollView {
        var scalingHeaderScrollView = self
        scalingHeaderScrollView._isLoading = isLoading
        scalingHeaderScrollView.didPullToRefresh = perform
        return scalingHeaderScrollView
    }

    /// Allows content scroll reset, need to change Binding to `true`
    func scrollToTop(resetScroll: Binding<Bool>) -> ScalingHeaderScrollView {
        var scalingHeaderScrollView = self
        scalingHeaderScrollView._scrollToTop = resetScroll
        return scalingHeaderScrollView
    }

    /// Changes min and max heights of Header
    func height(min: CGFloat = 150.0, max: CGFloat = 350.0) -> ScalingHeaderScrollView {
        var scalingHeaderScrollView = self
        scalingHeaderScrollView.minHeight = min
        scalingHeaderScrollView.maxHeight = max
        return scalingHeaderScrollView
    }

    /// When scrolling up - switch between actual header collapse and simply moving it up
    func allowsHeaderCollapse() -> ScalingHeaderScrollView {
        var scalingHeaderScrollView = self
        scalingHeaderScrollView.allowsHeaderCollapseFlag = true
        return scalingHeaderScrollView
    }

    /// When scrolling down - enable/disable header scale
    func allowsHeaderGrowth() -> ScalingHeaderScrollView {
        var scalingHeaderScrollView = self
        scalingHeaderScrollView.allowsHeaderGrowthFlag = true
        return scalingHeaderScrollView
    }

    /// Enable/disable header snap (once you lift your finger header snaps either to min or max height automatically)
    func allowsHeaderSnap() -> ScalingHeaderScrollView {
        var scalingHeaderScrollView = self
        scalingHeaderScrollView.allowsHeaderSnapFlag = true
        return scalingHeaderScrollView
    }

    /// Hiddes scroll indicators
    func hideScrollIndicators() -> ScalingHeaderScrollView {
        var scalingHeaderScrollView = self
        scalingHeaderScrollView.showsIndicators = false
        return scalingHeaderScrollView
    }
}
