//
// Seaglass, a native macOS Matrix client
// Copyright © 2018, Neil Alexander
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import Cocoa
import SwiftMatrixSDK
import Down

class MainViewRoomController: NSViewController, MatrixRoomDelegate, NSTableViewDelegate, NSTableViewDataSource {
    
    @IBOutlet var RoomName: NSTokenField!
    @IBOutlet var RoomTopic: NSTextField!
    @IBOutlet var RoomMessageInput: NSTextField!
    @IBOutlet var RoomMessageScrollView: NSScrollView!
    @IBOutlet var RoomMessageClipView: NSClipView!
    @IBOutlet var RoomMessageTableView: MainViewTableView!
    @IBOutlet var RoomInfoButton: NSButton!
    @IBOutlet var RoomPartButton: NSButton!
    @IBOutlet var RoomInsertButton: NSButton!
    @IBOutlet var RoomEncryptionButton: NSButton!
    
    weak public var mainController: MainViewController?
    
    var roomId: String = ""

    @IBAction func messageEntryFieldSubmit(_ sender: NSTextField) {
        if roomId == "" {
            return
        }
        
        sender.isEnabled = false
        
        var formattedText: String
        let unformattedText = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = DownOptions(rawValue: 1 << 3)
        do {
            // TODO: Make sure this is suitably sanitised
            formattedText = try Down(markdownString: unformattedText).toHTML(options)
            formattedText = formattedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if formattedText.hasPrefix("<p>") {
                formattedText = String(formattedText.dropFirst(3))
            }
            if formattedText.hasSuffix("</p>") {
                formattedText = String(formattedText.dropLast(4))
            }
        } catch {
            formattedText = unformattedText
        }
        
        var returnedEvent: MXEvent?
        if sender.stringValue.starts(with: "/me ") {
            let startIndex = unformattedText.index(unformattedText.startIndex, offsetBy: 4)
            MatrixServices.inst.session.room(withRoomId: roomId).sendEmote(String(unformattedText[startIndex...]), localEcho: &returnedEvent) { (response) in
                if case .success( _) = response {
                    sender.stringValue = ""
                    MatrixServices.inst.eventCache[self.roomId]?.append(returnedEvent!)
                    self.matrixDidRoomMessage(event: returnedEvent!, direction: .forwards, roomState: MatrixServices.inst.session.room(withRoomId: self.roomId).state)
                }
                sender.isEnabled = true
                sender.becomeFirstResponder()
            }
        } else {
            MatrixServices.inst.session.room(withRoomId: roomId).sendTextMessage(unformattedText, formattedText: formattedText, localEcho: &returnedEvent) { (response) in
                if case .success( _) = response {
                    sender.stringValue = ""
                    MatrixServices.inst.eventCache[self.roomId]?.append(returnedEvent!)
                    self.matrixDidRoomMessage(event: returnedEvent!, direction: .forwards, roomState: MatrixServices.inst.session.room(withRoomId: self.roomId).state)
                }
                sender.isEnabled = true
                sender.becomeFirstResponder()
            }
        }
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
    }

    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if segue.identifier != nil {
            switch segue.identifier!.rawValue {
            case "SegueToRoomSettings":
                if let dest = segue.destinationController as? RoomSettingsController {
                    dest.roomId = roomId
                }
                break
            default:
                return
            }
        }
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        if !MatrixServices.inst.eventCache.keys.contains(roomId) {
            return 0
        }
        if roomId == "" || MatrixServices.inst.eventCache[roomId] == nil {
            return 0
        }
        return (MatrixServices.inst.eventCache[roomId]?.count)!
    }
    
    func tableView(_ tableView: NSTableView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, row: Int) {
        let event = MatrixServices.inst.eventCache[roomId]![row]
        MatrixServices.inst.session.room(withRoomId: roomId).acknowledgeEvent(event, andUpdateReadMarker: true)
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let event = MatrixServices.inst.eventCache[roomId]![row]
        
        switch event.type {
        case "m.room.message":
            if event.sender == MatrixServices.inst.client?.credentials.userId {
                if row >= 1 && event.sender == MatrixServices.inst.eventCache[roomId]![row-1].sender && event.type == MatrixServices.inst.eventCache[roomId]![row-1].type {
                    let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "RoomMessageEntryOutboundCoalesced"), owner: self) as? RoomMessageEntry
                    if event.content["formatted_body"] != nil {
                        cell?.RoomMessageEntryOutboundCoalescedText.attributedStringValue = (event.content["formatted_body"] as! String).trimmingCharacters(in: .whitespacesAndNewlines).toAttributedStringFromHTML(justify: .right)
                    } else if event.content["body"] != nil {
                        cell?.RoomMessageEntryOutboundCoalescedText.stringValue = (event.content["body"] as! String).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    return cell
                } else {
                    let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "RoomMessageEntryOutbound"), owner: self) as? RoomMessageEntry
                    cell?.RoomMessageEntryOutboundFrom.stringValue = MatrixServices.inst.session.room(withRoomId: roomId).state.memberName(event.sender) ?? event.sender as String
                    cell?.RoomMessageEntryOutboundIcon.setAvatar(forUserId: event.sender)
                    if event.content["formatted_body"] != nil {
                        cell?.RoomMessageEntryOutboundText.attributedStringValue = (event.content["formatted_body"] as! String).trimmingCharacters(in: .whitespacesAndNewlines).toAttributedStringFromHTML(justify: .right)
                    } else if event.content["body"] != nil {
                        cell?.RoomMessageEntryOutboundText.stringValue = (event.content["body"] as! String).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if event.sentState == MXEventSentStateSending {
                        cell?.alphaValue = 0.4
                    }
                    return cell
                }
            } else {
                if row >= 1 && event.sender == MatrixServices.inst.eventCache[roomId]![row-1].sender && event.type == MatrixServices.inst.eventCache[roomId]![row-1].type {
                    let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "RoomMessageEntryInboundCoalesced"), owner: self) as? RoomMessageEntry
                    if event.content["formatted_body"] != nil {
                        cell?.RoomMessageEntryInboundCoalescedText.attributedStringValue = (event.content["formatted_body"] as! String).trimmingCharacters(in: .whitespacesAndNewlines).toAttributedStringFromHTML(justify: .left)
                    } else if event.content["body"] != nil {
                        cell?.RoomMessageEntryInboundCoalescedText.stringValue = (event.content["body"] as! String).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    return cell
                } else {
                    let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "RoomMessageEntryInbound"), owner: self) as? RoomMessageEntry
                    cell?.RoomMessageEntryInboundFrom.stringValue = MatrixServices.inst.session.room(withRoomId: roomId).state.memberName(event.sender) ?? event.sender as String
                    cell?.RoomMessageEntryInboundIcon.setAvatar(forUserId: event.sender)
                    if event.content["formatted_body"] != nil {
                        cell?.RoomMessageEntryInboundText.attributedStringValue = (event.content["formatted_body"] as! String).trimmingCharacters(in: .whitespacesAndNewlines).toAttributedStringFromHTML(justify: .left)
                    } else if event.content["body"] != nil {
                        cell?.RoomMessageEntryInboundText.stringValue = (event.content["body"] as! String).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if event.sentState == MXEventSentStateSending {
                        cell?.alphaValue = 0.4
                    }
                    return cell
                }
            }
        case "m.room.member":
            let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "RoomMessageEntryInline"), owner: self) as? RoomMessageEntry
            let displayName = MatrixServices.inst.session.room(withRoomId: roomId).state.memberName(event.stateKey) ?? event.stateKey as String
            switch event.content["membership"] as! String {
            case "join":    cell?.RoomMessageEntryInlineText.stringValue = "\(displayName) joined the room"; break
            case "leave":   cell?.RoomMessageEntryInlineText.stringValue = "\(displayName) left the room"; break
            case "invite":  cell?.RoomMessageEntryInlineText.stringValue = "\(displayName) was invited to the room"; break
            case "ban":     cell?.RoomMessageEntryInlineText.stringValue = "\(displayName) was banned from the room"; break
            default:        cell?.RoomMessageEntryInlineText.stringValue = "\(displayName) unknown event: \(event.stateKey)"; break
            }
            return cell
        case "m.room.name":
            let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "RoomMessageEntryInline"), owner: self) as? RoomMessageEntry
            cell?.RoomMessageEntryInlineText.stringValue = "Room renamed to \(event.content["name"] as! String)"
            return cell
        case "m.room.topic":
            let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "RoomMessageEntryInline"), owner: self) as? RoomMessageEntry
            cell?.RoomMessageEntryInlineText.stringValue = "Topic changed to \(event.content["topic"] as! String)"
            return cell
        case "m.room.canonical_alias":
            let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "RoomMessageEntryInline"), owner: self) as? RoomMessageEntry
            cell?.RoomMessageEntryInlineText.stringValue = "Primary room alias set to \(event.content["alias"] as! String)"
            return cell
        case "m.room.create":
            let displayName = MatrixServices.inst.session.room(withRoomId: roomId).state.memberName(event.content["creator"] as! String) ?? event.content["creator"] as! String
            let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "RoomMessageEntryInline"), owner: self) as? RoomMessageEntry
            cell?.RoomMessageEntryInlineText.stringValue = "Room created by \(displayName)"
            return cell
        default:
            let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "RoomMessageEntryInline"), owner: self) as? RoomMessageEntry
            cell?.RoomMessageEntryInlineText.stringValue = "Unknown event \(event.type)"
            print(event)
            return cell
        }
    }
    
    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        let scrollview = tableView.enclosingScrollView!
        let y1 = scrollview.documentView!.intrinsicContentSize.height - RoomMessageTableView.enclosingScrollView!.contentSize.height
        let y2 = scrollview.documentVisibleRect.origin.y
        if abs(y1 - y2) < 32 {
            RoomMessageTableView.scroll(NSPoint(x: 0, y: y1 + rowView.intrinsicContentSize.height + (RoomMessageTableView.enclosingScrollView?.contentInsets.bottom)!))
        }
    }
    
    func uiDidSelectRoom(entry: RoomListEntry) {
        if entry.roomsCacheEntry?.roomId == nil {
            return
        }

        RoomName.isEnabled = true
        RoomInfoButton.isEnabled = true
        RoomPartButton.isEnabled = true
        RoomEncryptionButton.isEnabled = true
        RoomInsertButton.isEnabled = true
        RoomMessageInput.isEnabled = true

        RoomName.stringValue = entry.RoomListEntryName.stringValue
        RoomTopic.stringValue = entry.RoomListEntryTopic.stringValue.components(separatedBy: "\n")[1]
        
        roomId = (entry.roomsCacheEntry?.roomId)!

        RoomMessageTableView.reloadData()
        
        if entry.roomsCacheEntry!.encrypted() {
            RoomEncryptionButton.image = NSImage(named: NSImage.Name.lockLockedTemplate)
        } else {
            RoomEncryptionButton.image = NSImage(named: NSImage.Name.lockUnlockedTemplate)
        }
    }
    
    func matrixDidRoomMessage(event: MXEvent, direction: MXTimelineDirection, roomState: MXRoomState) {
        if event.roomId == nil {
            return
        }
        if !MatrixServices.inst.eventCache[event.roomId]!.contains(where: { $0.eventId == event.eventId }) {
            return
        }
        switch event.type {
        case "m.typing":
            return
        case "m.receipt":
            return
        case "m.room.message":
            fallthrough
        case "m.room.member":
            RoomMessageTableView.noteNumberOfRowsChanged()
            return
        default:
            break
        }
    }
    func matrixDidRoomUserJoin() {}
    func martixDidRoomUserPart() {}
    
}
