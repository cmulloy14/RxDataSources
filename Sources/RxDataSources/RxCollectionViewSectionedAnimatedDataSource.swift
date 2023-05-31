//
//  RxCollectionViewSectionedAnimatedDataSource.swift
//  RxExample
//
//  Created by Krunoslav Zaher on 7/2/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(iOS) || os(tvOS)
import Foundation
import UIKit
#if !RX_NO_MODULE
import RxSwift
import RxCocoa
#endif
import Differentiator

open class RxCollectionViewSectionedAnimatedDataSource<Section: AnimatableSectionModelType>
    : CollectionViewSectionedDataSource<Section>
    , RxCollectionViewDataSourceType {
    public typealias Element = [Section]
    public typealias DecideViewTransition = (CollectionViewSectionedDataSource<Section>, UICollectionView, [Changeset<Section>]) -> ViewTransition

    // animation configuration
    public var animationConfiguration: AnimationConfiguration

    public var isAnimating: Observable<Bool> { isAnimatingRelay.asObservable() }
    private var isAnimatingRelay = BehaviorRelay<Bool>(value: false)
    private let fadeDeleteAnimationTime: TimeInterval?
    /// Calculates view transition depending on type of changes
    public var decideViewTransition: DecideViewTransition

    public init(
        animationConfiguration: AnimationConfiguration = AnimationConfiguration(),
        decideViewTransition: @escaping DecideViewTransition = { _, _, _ in .animated },
        configureCell: @escaping ConfigureCell,
        configureSupplementaryView: ConfigureSupplementaryView? = nil,
        moveItem: @escaping MoveItem = { _, _, _ in () },
        canMoveItemAtIndexPath: @escaping CanMoveItemAtIndexPath = { _, _ in false },
        fadeDeleteAnimationTime: TimeInterval? = nil
        ) {
        self.animationConfiguration = animationConfiguration
        self.decideViewTransition = decideViewTransition
        self.fadeDeleteAnimationTime = fadeDeleteAnimationTime
        super.init(
            configureCell: configureCell,
            configureSupplementaryView: configureSupplementaryView,
            moveItem: moveItem,
            canMoveItemAtIndexPath: canMoveItemAtIndexPath
        )
    }

    // there is no longer limitation to load initial sections with reloadData
    // but it is kept as a feature everyone got used to
    var dataSet = false

    open func collectionView(_ collectionView: UICollectionView, observedEvent: Event<Element>) {
        Binder(self) { [fadeDeleteAnimationTime, isAnimatingRelay] dataSource, newSections in
            #if DEBUG
                dataSource._dataSourceBound = true
            #endif
            if !dataSource.dataSet {
                dataSource.dataSet = true
                dataSource.setSections(newSections)
                collectionView.reloadData()
            }
            else {
                // if view is not in view hierarchy, performing batch updates will crash the app
                if collectionView.window == nil {
                    dataSource.setSections(newSections)
                    collectionView.reloadData()
                    return
                }
                let oldSections = dataSource.sectionModels
                do {
                    let differences = try Diff.differencesForSectionedView(initialSections: oldSections, finalSections: newSections)

                    switch dataSource.decideViewTransition(dataSource, collectionView, differences) {
                    case .animated:
                        // each difference must be run in a separate 'performBatchUpdates', otherwise it crashes.
                        // this is a limitation of Diff tool
                        for difference in differences {
                          if difference.deletedItems.count == 1, let fadeDeleteAnimationTime = fadeDeleteAnimationTime, let item = difference.deletedItems.first {
                            let indexPath = IndexPath(item: item.itemIndex, section: item.sectionIndex)
                            let cell = collectionView.cellForItem(at: indexPath)
                            isAnimatingRelay.accept(true)
                            UIView.animate(withDuration: fadeDeleteAnimationTime, delay: 0, animations: { [cell] in
                              cell?.alpha = 0
                            }) { _ in
                              let updateBlock = {
                                // sections must be set within updateBlock in 'performBatchUpdates'
                                dataSource.setSections(difference.finalSections)
                                collectionView.batchUpdates(difference, animationConfiguration: dataSource.animationConfiguration)
                              }
                              collectionView.performBatchUpdates(updateBlock, completion: {  _ in
                                isAnimatingRelay.accept(false)
                              })
                            }
                          }
                          else {
                            let updateBlock = {
                              // sections must be set within updateBlock in 'performBatchUpdates'
                              dataSource.setSections(difference.finalSections)
                              collectionView.batchUpdates(difference, animationConfiguration: dataSource.animationConfiguration)
                            }
                            collectionView.performBatchUpdates(updateBlock, completion: nil)
                          }
                        }

                    case .reload:
                        dataSource.setSections(newSections)
                        collectionView.reloadData()
                        return
                    }
                }
                catch let e {
                    rxDebugFatalError(e)
                    dataSource.setSections(newSections)
                    collectionView.reloadData()
                }
            }
        }.on(observedEvent)
    }
}
#endif
